defmodule ClaudeCode.Adapter.Port.ProxyIntegrationTest do
  @moduledoc """
  Integration tests that exercise the full proxy routing pipeline through
  a running Adapter.Port GenServer with a real CallbackProxy.

  These tests verify that inbound control requests from the CLI are correctly
  routed through handle_inbound_control_request/2 to either the local
  hook registry or the CallbackProxy.
  """
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Node.CallbackProxy
  alias ClaudeCode.Adapter.Port, as: AdapterPort
  alias ClaudeCode.Hook.Registry, as: HookRegistry

  # ============================================================================
  # Test Hook Module
  # ============================================================================

  defmodule AllowHook do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  defmodule CanUseToolCallback do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  # ============================================================================
  # Helper: build a mock CLI script that sends inbound control requests
  # ============================================================================

  defp build_control_request_script(control_requests, response_file) do
    # Build lines that send each control request and read the response.
    # Responses are written to a temp file so tests can verify content.
    request_lines =
      control_requests
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {request_json, idx} ->
        escaped = String.replace(request_json, "'", "'\\''")

        """
            echo '#{escaped}'
            IFS= read -r resp_#{idx}
            echo "$resp_#{idx}" >> "#{response_file}"
        """
      end)

    """
    #!/bin/bash

    # Phase 1: Handle SDK control requests (initialize, etc.)
    while IFS= read -r line; do
      if echo "$line" | grep -q '"type":"control_request"'; then
        REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
        echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
      else
        # Got user message — emit system init, then send our control requests
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"proxy-int","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

    #{request_lines}

        # Emit result
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"done","session_id":"proxy-int","total_cost_usd":0.001,"usage":{}}'
        break
      fi
    done

    # Drain remaining stdin to prevent broken pipe
    while IFS= read -r line; do
      if echo "$line" | grep -q '"type":"control_request"'; then
        REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
        echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
      fi
    done
    exit 0
    """
  end

  defp setup_mock_cli(control_requests) do
    response_file = Path.join(System.tmp_dir!(), "proxy_int_#{:rand.uniform(999_999)}")
    File.write!(response_file, "")

    mock_dir = Path.join(System.tmp_dir!(), "claude_proxy_int_#{:rand.uniform(999_999)}")
    File.mkdir_p!(mock_dir)

    mock_script = Path.join(mock_dir, "claude")
    script_content = build_control_request_script(control_requests, response_file)
    File.write!(mock_script, script_content)
    File.chmod!(mock_script, 0o755)

    on_exit(fn ->
      File.rm_rf!(mock_dir)
      File.rm(response_file)
    end)

    {mock_script, response_file}
  end

  defp read_responses(response_file, expected_count, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    poll = fn poll_fn ->
      content = File.read!(response_file)
      lines = content |> String.trim() |> String.split("\n", trim: true)

      if length(lines) >= expected_count do
        Enum.map(lines, &Jason.decode!/1)
      else
        if System.monotonic_time(:millisecond) >= deadline do
          raise "Timed out waiting for #{expected_count} responses, got #{length(lines)}: #{content}"
        end

        Process.sleep(50)
        poll_fn.(poll_fn)
      end
    end

    poll.(poll)
  end

  defp start_session_with_proxy(mock_script, proxy, remote_registry, opts \\ []) do
    callback_timeout = Keyword.get(opts, :callback_timeout, 5_000)

    # Start the session with the mock CLI. We pass callback_proxy and
    # hook_registry through a workaround: start the adapter directly.
    session = self()

    {:ok, adapter} =
      AdapterPort.start_link(session,
        cli_path: mock_script,
        api_key: "test-key",
        callback_proxy: proxy,
        hook_registry: remote_registry,
        callback_timeout: callback_timeout,
        sdk_mcp_servers: %{}
      )

    # Wait for the adapter to be ready (it sends status notifications)
    wait_for_ready(adapter)
    adapter
  end

  defp wait_for_ready(adapter, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    poll = fn poll_fn ->
      state = :sys.get_state(adapter)

      if state.status == :ready do
        :ok
      else
        if System.monotonic_time(:millisecond) >= deadline do
          raise "Timed out waiting for adapter to be ready (status: #{inspect(state.status)})"
        end

        # Drain any messages sent to us (status notifications)
        receive do
          _ -> :ok
        after
          10 -> :ok
        end

        poll_fn.(poll_fn)
      end
    end

    poll.(poll)
  end

  # ============================================================================
  # MCP Routing Integration Tests
  # ============================================================================

  describe "MCP routing through proxy" do
    test "mcp_message control request is routed to CallbackProxy and response returned" do
      # Build the control request the mock CLI will send
      mcp_request =
        Jason.encode!(%{
          type: "control_request",
          request_id: "cli_mcp_1",
          request: %{
            subtype: "mcp_message",
            server_name: "test-tools",
            message: %{
              "jsonrpc" => "2.0",
              "id" => 1,
              "method" => "tools/call",
              "params" => %{"name" => "add", "arguments" => %{"x" => 2, "y" => 3}}
            }
          }
        })

      {mock_script, response_file} = setup_mock_cli([mcp_request])

      # Start proxy with the test MCP server
      {:ok, proxy} =
        CallbackProxy.start_link(
          mcp_servers: %{"test-tools" => ClaudeCode.TestTools},
          hook_registry: %HookRegistry{}
        )

      adapter = start_session_with_proxy(mock_script, proxy, %HookRegistry{})

      # Send a query to trigger the mock CLI's control request phase
      AdapterPort.send_query(adapter, "req_1", "test", [])

      # Read the response the mock CLI received
      [response] = read_responses(response_file, 1)

      # The response should be a control_response with the MCP result
      assert response["type"] == "control_response"
      resp = response["response"]
      assert resp["subtype"] == "success"
      assert resp["request_id"] == "cli_mcp_1"

      # The MCP server should have computed 2 + 3 = 5
      mcp_response = resp["response"]["mcp_response"]
      assert mcp_response["result"]["content"] == [%{"text" => "5", "type" => "text"}]

      GenServer.stop(adapter)
      GenServer.stop(proxy)
    end
  end

  # ============================================================================
  # can_use_tool Routing Integration Tests
  # ============================================================================

  describe "can_use_tool routing through proxy" do
    test "can_use_tool control request is routed to CallbackProxy" do
      cut_request =
        Jason.encode!(%{
          type: "control_request",
          request_id: "cli_cut_1",
          request: %{
            subtype: "can_use_tool",
            tool_name: "Bash",
            input: %{"command" => "ls"}
          }
        })

      {mock_script, response_file} = setup_mock_cli([cut_request])

      # Start proxy with a can_use_tool callback
      {:ok, proxy} =
        CallbackProxy.start_link(hook_registry: %{} |> HookRegistry.new(CanUseToolCallback) |> elem(0))

      adapter = start_session_with_proxy(mock_script, proxy, %HookRegistry{})

      AdapterPort.send_query(adapter, "req_1", "test", [])

      [response] = read_responses(response_file, 1)

      assert response["type"] == "control_response"
      resp = response["response"]
      assert resp["subtype"] == "success"
      assert resp["response"]["behavior"] == "allow"

      GenServer.stop(adapter)
      GenServer.stop(proxy)
    end
  end

  # ============================================================================
  # Hook Callback Routing Integration Tests
  # ============================================================================

  describe "hook_callback routing" do
    test "hook_callback for remote hook is handled locally by Adapter.Port" do
      # Build a hook_callback request targeting hook_0 (which will be in the
      # remote registry, handled locally by Adapter.Port)
      hook_request =
        Jason.encode!(%{
          type: "control_request",
          request_id: "cli_hook_1",
          request: %{
            subtype: "hook_callback",
            callback_id: "hook_0",
            input: %{"tool_name" => "Bash"},
            tool_use_id: "tu_1"
          }
        })

      {mock_script, response_file} = setup_mock_cli([hook_request])

      # Create a registry with a remote hook (this is what Adapter.Port holds)
      hooks = %{PreToolUse: [%{hooks: [AllowHook], where: :remote}]}
      {full_registry, _wire} = HookRegistry.new(hooks, nil)
      {_local, remote_registry} = HookRegistry.split(full_registry)

      # Start proxy (empty — the hook is remote, so it shouldn't be called)
      {:ok, proxy} = CallbackProxy.start_link(hook_registry: %HookRegistry{})

      adapter = start_session_with_proxy(mock_script, proxy, remote_registry)

      AdapterPort.send_query(adapter, "req_1", "test", [])

      [response] = read_responses(response_file, 1)

      assert response["type"] == "control_response"
      resp = response["response"]
      assert resp["subtype"] == "success"
      # AllowHook returns :allow → to_hook_callback_wire(:allow) → %{}
      assert resp["response"] == %{}

      GenServer.stop(adapter)
      GenServer.stop(proxy)
    end

    test "hook_callback for local hook is delegated to CallbackProxy" do
      # Build a hook_callback request targeting hook_0 (which will NOT be in
      # the remote registry, so Adapter.Port delegates to proxy)
      hook_request =
        Jason.encode!(%{
          type: "control_request",
          request_id: "cli_hook_2",
          request: %{
            subtype: "hook_callback",
            callback_id: "hook_0",
            input: %{"tool_name" => "Bash"},
            tool_use_id: "tu_2"
          }
        })

      {mock_script, response_file} = setup_mock_cli([hook_request])

      # Create registries — hook_0 is LOCAL, so it goes in the proxy
      hooks = %{PreToolUse: [%{hooks: [AllowHook]}]}
      {full_registry, _wire} = HookRegistry.new(hooks, nil)
      {local_registry, remote_registry} = HookRegistry.split(full_registry)

      # Proxy holds the local hook
      {:ok, proxy} = CallbackProxy.start_link(hook_registry: local_registry)

      # Adapter.Port holds the remote registry (empty in this case)
      adapter = start_session_with_proxy(mock_script, proxy, remote_registry)

      AdapterPort.send_query(adapter, "req_1", "test", [])

      [response] = read_responses(response_file, 1)

      assert response["type"] == "control_response"
      resp = response["response"]
      assert resp["subtype"] == "success"
      # AllowHook returns :allow → to_hook_callback_wire(:allow) → %{}
      assert resp["response"] == %{}

      GenServer.stop(adapter)
      GenServer.stop(proxy)
    end
  end
end
