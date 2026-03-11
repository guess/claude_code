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
  # Test Hook Modules
  # ============================================================================

  defmodule AllowHook do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp start_adapter_with_proxy(mock_script, proxy, remote_registry, opts \\ []) do
    callback_timeout = Keyword.get(opts, :callback_timeout, 5_000)
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

    MockCLI.wait_until_adapter_ready(adapter)
    adapter
  end

  # ============================================================================
  # MCP Routing Integration Tests
  # ============================================================================

  describe "MCP routing through proxy" do
    test "mcp_message control request is routed to CallbackProxy and response returned" do
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

      {mock_script, response_file} = MockCLI.setup_with_control_requests([mcp_request])

      {:ok, proxy} =
        CallbackProxy.start_link(
          mcp_servers: %{"test-tools" => ClaudeCode.TestTools},
          hook_registry: %HookRegistry{}
        )

      adapter = start_adapter_with_proxy(mock_script, proxy, %HookRegistry{})
      AdapterPort.send_query(adapter, "req_1", "test", [])

      [response] = MockCLI.read_responses(response_file, 1)

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
  # Hook Callback Routing Integration Tests
  # ============================================================================

  describe "hook_callback routing" do
    test "hook_callback for remote hook is handled locally by Adapter.Port" do
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

      {mock_script, response_file} = MockCLI.setup_with_control_requests([hook_request])

      # Remote hook lives in Adapter.Port's registry — proxy shouldn't be called
      hooks = %{PreToolUse: [%{hooks: [AllowHook], where: :remote}]}
      {full_registry, _wire} = HookRegistry.new(hooks)
      {_local, remote_registry} = HookRegistry.split(full_registry)

      {:ok, proxy} = CallbackProxy.start_link(hook_registry: %HookRegistry{})
      adapter = start_adapter_with_proxy(mock_script, proxy, remote_registry)
      AdapterPort.send_query(adapter, "req_1", "test", [])

      [response] = MockCLI.read_responses(response_file, 1)

      assert response["type"] == "control_response"
      resp = response["response"]
      assert resp["subtype"] == "success"
      # AllowHook returns :allow → to_hook_callback_wire(:allow) → %{}
      assert resp["response"] == %{}

      GenServer.stop(adapter)
      GenServer.stop(proxy)
    end

    test "hook_callback for local hook is delegated to CallbackProxy" do
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

      {mock_script, response_file} = MockCLI.setup_with_control_requests([hook_request])

      # Local hook lives in the proxy's registry — Adapter.Port delegates
      hooks = %{PreToolUse: [%{hooks: [AllowHook]}]}
      {full_registry, _wire} = HookRegistry.new(hooks)
      {local_registry, remote_registry} = HookRegistry.split(full_registry)

      {:ok, proxy} = CallbackProxy.start_link(hook_registry: local_registry)
      adapter = start_adapter_with_proxy(mock_script, proxy, remote_registry)
      AdapterPort.send_query(adapter, "req_1", "test", [])

      [response] = MockCLI.read_responses(response_file, 1)

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
