defmodule ClaudeCode.Adapter.RemoteTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Remote
  alias ClaudeCode.Adapter.Remote.Backend
  alias ClaudeCode.Adapter.Remote.Transport

  # Helper to build valid system init message JSON
  defp system_init_json(session_id \\ "test-session") do
    ~s({"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"#{session_id}","tools":["Bash","Read"],"mcp_servers":[],"model":"claude-opus","permissionMode":"default","apiKeySource":"env","slash_commands":[],"output_style":"default","agents":[],"skills":[],"plugins":[]})
  end

  # Helper to build valid assistant message JSON
  defp assistant_message_json(text, session_id \\ "test-session") do
    ~s({"type":"assistant","message":{"id":"msg_123","type":"message","role":"assistant","model":"claude-opus","content":[{"type":"text","text":"#{text}"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5}},"parent_tool_use_id":null,"session_id":"#{session_id}"})
  end

  # Helper to build valid result message JSON
  defp result_message_json(result, session_id \\ "test-session") do
    ~s({"type":"result","subtype":"success","is_error":false,"duration_ms":100.0,"duration_api_ms":80.0,"num_turns":1,"result":"#{result}","session_id":"#{session_id}","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}})
  end

  # ============================================================================
  # Transport Behaviour Tests
  # ============================================================================

  describe "Transport behaviour" do
    test "defines required callbacks" do
      callbacks = Transport.behaviour_info(:callbacks)

      assert {:connect, 2} in callbacks
      assert {:send_input, 2} in callbacks
      assert {:disconnect, 1} in callbacks
      assert {:alive?, 1} in callbacks
    end
  end

  # ============================================================================
  # Backend Behaviour Tests
  # ============================================================================

  describe "Backend behaviour" do
    test "defines required callbacks" do
      callbacks = Backend.behaviour_info(:callbacks)

      assert {:provision, 2} in callbacks
      assert {:terminate, 2} in callbacks
      assert {:get_info, 2} in callbacks
      assert {:available?, 1} in callbacks
      assert {:health_check, 2} in callbacks
    end
  end

  # ============================================================================
  # Custom Backend Tests
  # ============================================================================

  describe "Backend.Custom" do
    alias ClaudeCode.Adapter.Remote.Backend.Custom

    test "provision returns container info with endpoint" do
      endpoint = "wss://example.com:8080"

      {:ok, info} = Custom.provision(%{}, endpoint: endpoint)

      assert info.endpoint == endpoint
      assert info.status == :running
      assert info.metadata.backend == :custom
      assert String.starts_with?(info.id, "custom-")
    end

    test "terminate is a no-op and returns :ok" do
      assert Custom.terminate("custom-123", []) == :ok
    end

    test "get_info returns info when endpoint provided" do
      endpoint = "wss://example.com:8080"

      {:ok, info} = Custom.get_info("custom-123", endpoint: endpoint)

      assert info.id == "custom-123"
      assert info.endpoint == endpoint
      assert info.status == :unknown
    end

    test "get_info returns error without endpoint" do
      assert Custom.get_info("custom-123", []) == {:error, :not_found}
    end

    test "available? always returns true" do
      assert Custom.available?([]) == true
    end

    test "health_check always returns :healthy" do
      assert Custom.health_check("custom-123", []) == :healthy
    end
  end

  # ============================================================================
  # Remote Adapter Behaviour Tests
  # ============================================================================

  describe "adapter behaviour" do
    test "implements ClaudeCode.Adapter behaviour" do
      behaviours = Remote.__info__(:attributes)[:behaviour] || []
      assert ClaudeCode.Adapter in behaviours
    end
  end

  # ============================================================================
  # Remote Adapter Initialization Tests
  # ============================================================================

  describe "init/1" do
    test "requires endpoint option" do
      session_pid = self()

      assert_raise ArgumentError, ~r/requires :endpoint option/, fn ->
        Remote.init({session_pid, []})
      end
    end

    test "accepts endpoint in remote options" do
      session_pid = self()
      opts = [remote: [endpoint: "wss://example.com:8080"]]

      {:ok, state} = Remote.init({session_pid, opts})

      assert state.endpoint == "wss://example.com:8080"
      assert state.session == session_pid
    end

    test "accepts endpoint as top-level option" do
      session_pid = self()
      opts = [endpoint: "wss://example.com:8080"]

      {:ok, state} = Remote.init({session_pid, opts})

      assert state.endpoint == "wss://example.com:8080"
    end

    test "uses default transport and backend modules" do
      session_pid = self()
      opts = [endpoint: "wss://example.com:8080"]

      {:ok, state} = Remote.init({session_pid, opts})

      assert state.transport_module == Transport.WebSocket
      assert state.backend_module == Backend.Custom
    end

    test "allows custom transport and backend modules" do
      session_pid = self()

      opts = [
        remote: [
          endpoint: "wss://example.com:8080",
          transport: MyCustomTransport,
          backend: MyCustomBackend
        ]
      ]

      {:ok, state} = Remote.init({session_pid, opts})

      assert state.transport_module == MyCustomTransport
      assert state.backend_module == MyCustomBackend
    end

    test "extracts api_key from options" do
      session_pid = self()
      opts = [endpoint: "wss://example.com:8080", api_key: "sk-ant-test"]

      {:ok, state} = Remote.init({session_pid, opts})

      assert state.api_key == "sk-ant-test"
    end
  end

  # ============================================================================
  # Transport Message Handling Tests
  # ============================================================================

  describe "handle_info/2 for transport messages" do
    setup do
      session_pid = self()
      opts = [endpoint: "wss://example.com:8080"]
      {:ok, state} = Remote.init({session_pid, opts})
      %{state: state, session_pid: session_pid}
    end

    test "handles transport_connected message", %{state: state} do
      {:noreply, new_state} = Remote.handle_info({:transport_connected, "wss://example.com:8080"}, state)

      # State should remain unchanged
      assert new_state == state
    end

    test "handles transport_disconnected message with no active request", %{state: state} do
      {:noreply, new_state} = Remote.handle_info({:transport_disconnected, :normal}, state)

      assert new_state.transport == nil
      assert new_state.current_request == nil
      assert new_state.buffer == ""
    end

    test "handles transport_disconnected message with active request", %{state: state} do
      request_id = make_ref()
      state_with_request = %{state | current_request: request_id}

      {:noreply, _new_state} = Remote.handle_info({:transport_disconnected, :error}, state_with_request)

      assert_receive {:adapter_error, ^request_id, {:connection_lost, :error}}
    end

    test "handles transport_error message with active request", %{state: state} do
      request_id = make_ref()
      state_with_request = %{state | current_request: request_id}

      {:noreply, _new_state} = Remote.handle_info({:transport_error, :timeout}, state_with_request)

      assert_receive {:adapter_error, ^request_id, {:transport_error, :timeout}}
    end
  end

  # ============================================================================
  # Transport Data Processing Tests
  # ============================================================================

  describe "handle_info/2 for transport data" do
    setup do
      session_pid = self()
      opts = [endpoint: "wss://example.com:8080"]
      {:ok, state} = Remote.init({session_pid, opts})
      %{state: state, session_pid: session_pid}
    end

    test "buffers incomplete JSON lines", %{state: state} do
      state_with_request = %{state | current_request: make_ref()}
      partial_json = ~s({"type":"assis)

      {:noreply, new_state} = Remote.handle_info({:transport_data, partial_json}, state_with_request)

      assert new_state.buffer == partial_json
    end

    test "processes complete JSON lines", %{state: state} do
      request_id = make_ref()
      state_with_request = %{state | current_request: request_id}

      {:noreply, _new_state} = Remote.handle_info({:transport_data, system_init_json() <> "\n"}, state_with_request)

      assert_receive {:adapter_message, ^request_id, message}
      assert message.type == :system
    end

    test "handles multiple lines in single data chunk", %{state: state} do
      request_id = make_ref()
      state_with_request = %{state | current_request: request_id}

      data = "#{system_init_json()}\n#{assistant_message_json("Hello")}\n"

      {:noreply, _new_state} = Remote.handle_info({:transport_data, data}, state_with_request)

      assert_receive {:adapter_message, ^request_id, system_msg}
      assert system_msg.type == :system

      assert_receive {:adapter_message, ^request_id, assistant_msg}
      assert assistant_msg.type == :assistant
    end

    test "sends adapter_done on result message", %{state: state} do
      request_id = make_ref()
      state_with_request = %{state | current_request: request_id, request_start_time: System.monotonic_time()}

      {:noreply, new_state} =
        Remote.handle_info({:transport_data, result_message_json("Hello!") <> "\n"}, state_with_request)

      assert_receive {:adapter_message, ^request_id, result_msg}
      assert result_msg.type == :result

      assert_receive {:adapter_done, ^request_id}

      # Request should be cleared
      assert new_state.current_request == nil
    end

    test "accumulates buffer across multiple data chunks", %{state: state} do
      request_id = make_ref()
      state_with_request = %{state | current_request: request_id}

      # Get a full system init JSON and split it
      full_system = system_init_json()

      # First chunk - partial (first 20 chars)
      chunk1 = String.slice(full_system, 0, 20)
      {:noreply, state1} = Remote.handle_info({:transport_data, chunk1}, state_with_request)
      assert state1.buffer == chunk1

      # Second chunk - rest of system message + newline + start of result
      chunk2 =
        String.slice(full_system, 20, String.length(full_system)) <>
          "\n" <> String.slice(result_message_json("done"), 0, 15)

      {:noreply, state2} = Remote.handle_info({:transport_data, chunk2}, state1)

      # Should have received system message
      assert_receive {:adapter_message, ^request_id, system_msg}
      assert system_msg.type == :system

      # Buffer should have partial result
      assert state2.buffer == String.slice(result_message_json("done"), 0, 15)

      # Third chunk - completes result message
      chunk3 = String.slice(result_message_json("done"), 15, String.length(result_message_json("done"))) <> "\n"

      state_with_time = %{state2 | request_start_time: System.monotonic_time()}
      {:noreply, state3} = Remote.handle_info({:transport_data, chunk3}, state_with_time)

      assert state3.buffer == ""
      assert_receive {:adapter_message, ^request_id, result_msg}
      assert result_msg.type == :result
      assert_receive {:adapter_done, ^request_id}
    end

    test "ignores data when no active request", %{state: state} do
      data = ~s({"type":"system","subtype":"init"}\n)

      {:noreply, new_state} = Remote.handle_info({:transport_data, data}, state)

      # No messages should be sent, but state should be cleared
      refute_receive {:adapter_message, _, _}
      assert new_state.buffer == ""
    end
  end

  # ============================================================================
  # Options Validation Tests
  # ============================================================================

  describe "options validation" do
    test "remote options are validated by NimbleOptions" do
      schema = ClaudeCode.Options.session_schema()
      remote_schema = Keyword.get(schema, :remote)

      assert remote_schema[:type] == :keyword_list
      assert is_list(remote_schema[:keys])
    end

    test "endpoint option is not passed to CLI" do
      args = ClaudeCode.Options.to_cli_args(endpoint: "wss://example.com")
      assert args == []
    end

    test "remote option is not passed to CLI" do
      args = ClaudeCode.Options.to_cli_args(remote: [endpoint: "wss://example.com"])
      assert args == []
    end
  end

  # ============================================================================
  # Mock Transport for Integration Tests
  # ============================================================================

  defmodule MockTransport do
    @moduledoc false
    @behaviour Transport

    @impl true
    def connect(endpoint, opts) do
      subscriber = Keyword.fetch!(opts, :subscriber)
      pid = spawn_link(fn -> mock_loop(subscriber, endpoint) end)
      {:ok, pid}
    end

    @impl true
    def send_input(transport, data) do
      send(transport, {:send, data})
      :ok
    end

    @impl true
    def disconnect(transport) do
      send(transport, :disconnect)
      :ok
    end

    @impl true
    def alive?(transport) do
      Process.alive?(transport)
    end

    defp mock_loop(subscriber, endpoint) do
      send(subscriber, {:transport_connected, endpoint})

      receive do
        {:send, _data} ->
          # Simulate response with valid message formats
          system_msg =
            ~s({"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/mock","session_id":"mock-123","tools":["Bash"],"mcp_servers":[],"model":"claude-opus","permissionMode":"default","apiKeySource":"env","slash_commands":[],"output_style":"default","agents":[],"skills":[],"plugins":[]})

          result_msg =
            ~s({"type":"result","subtype":"success","is_error":false,"duration_ms":50.0,"duration_api_ms":40.0,"num_turns":1,"result":"Mock response","session_id":"mock-123","total_cost_usd":0.0001,"usage":{"input_tokens":5,"output_tokens":10}})

          send(subscriber, {:transport_data, system_msg <> "\n"})
          send(subscriber, {:transport_data, result_msg <> "\n"})

          mock_loop(subscriber, endpoint)

        :disconnect ->
          :ok
      end
    end
  end

  describe "integration with mock transport" do
    test "full query flow with mock transport" do
      session_pid = self()

      opts = [
        remote: [
          endpoint: "wss://mock.example.com",
          transport: MockTransport
        ]
      ]

      {:ok, state} = Remote.init({session_pid, opts})
      request_id = make_ref()

      # Simulate ensure_connected + send_query flow
      {:ok, connected_state} = ensure_connected_mock(state)

      # Send query message
      message = ~s({"type":"user","content":"Hello"})
      MockTransport.send_input(connected_state.transport, message)

      new_state = %{connected_state | current_request: request_id, request_start_time: System.monotonic_time()}

      # Process incoming messages
      receive do
        {:transport_connected, _} -> :ok
      end

      receive do
        {:transport_data, data} ->
          {:noreply, state2} = Remote.handle_info({:transport_data, data}, new_state)

          receive do
            {:transport_data, data2} ->
              {:noreply, _state3} = Remote.handle_info({:transport_data, data2}, state2)
          end
      end

      # Verify messages received
      assert_receive {:adapter_message, ^request_id, system_msg}
      assert system_msg.type == :system

      assert_receive {:adapter_message, ^request_id, result_msg}
      assert result_msg.type == :result
      assert result_msg.result == "Mock response"

      assert_receive {:adapter_done, ^request_id}
    end

    defp ensure_connected_mock(state) do
      transport_opts = [
        subscriber: self(),
        connect_timeout: 5_000,
        reconnect_attempts: 1
      ]

      case state.transport_module.connect(state.endpoint, transport_opts) do
        {:ok, transport} ->
          {:ok, %{state | transport: transport, buffer: ""}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
