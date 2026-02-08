defmodule ClaudeCode.Adapter.CLIIntegrationTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.ResultMessage

  # ============================================================================
  # CLI Adapter interrupt/1 Tests
  # ============================================================================

  describe "interrupt/1 with no active query" do
    test "returns {:error, :no_active_request} when no query is running" do
      # Start a session -- the adapter starts with port: nil
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      # No query is running, so interrupt should return error
      assert {:error, :no_active_request} = ClaudeCode.interrupt(session)

      GenServer.stop(session)
    end
  end

  describe "interrupt/1 with active query" do
    setup do
      # Create a mock CLI that stays running (slow response)
      MockCLI.setup_with_script("""
      #!/bin/bash
      while IFS= read -r line; do
        # Respond very slowly - gives time to interrupt
        sleep 30
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"int-test","total_cost_usd":0.001,"usage":{}}'
      done
      exit 0
      """)
    end

    test "returns :ok and terminates stream without result message", %{
      mock_script: mock_script
    } do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key", cli_path: mock_script)

      # Start a streaming query in a separate task
      stream_task =
        Task.async(fn ->
          session
          |> ClaudeCode.stream("slow query")
          |> Enum.to_list()
        end)

      # Wait for the query to actually start being processed
      Process.sleep(300)

      # Interrupt the active query
      assert :ok = ClaudeCode.interrupt(session)

      # The stream should terminate (not hang forever)
      messages = Task.await(stream_task, 5_000)

      # Stream ended without a result message (interrupted before result arrived)
      assert is_list(messages)
      refute Enum.any?(messages, &match?(%ResultMessage{}, &1))

      GenServer.stop(session)
    end
  end

  # ============================================================================
  # CLI Adapter health/1 Tests
  # ============================================================================

  describe "health/1 before connection" do
    test "returns {:unhealthy, :not_connected} before any query" do
      # The CLI adapter starts with port: nil and only connects on first query.
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      health = ClaudeCode.health(session)
      assert {:unhealthy, :not_connected} = health

      GenServer.stop(session)
    end
  end

  describe "health/1 after connection" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash
      while IFS= read -r line; do
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"health-test","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"health-test","total_cost_usd":0.001,"usage":{}}'
      done
      exit 0
      """)
    end

    test "returns :healthy after a successful query", %{mock_script: mock_script} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key", cli_path: mock_script)

      # Run a query to trigger connection
      {:ok, _result} = MockCLI.sync_query(session, "hello")

      # Now the port should be alive
      health = ClaudeCode.health(session)
      assert :healthy = health

      GenServer.stop(session)
    end
  end

  # ============================================================================
  # Stream interrupted vs completed distinction
  # ============================================================================

  describe "stream completed normally" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash
      while IFS= read -r line; do
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"complete-test","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
        echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Hello there"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"complete-test"}'
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Hello there","session_id":"complete-test","total_cost_usd":0.001,"usage":{}}'
      done
      exit 0
      """)
    end

    test "normal completion includes a result message in the stream", %{
      mock_script: mock_script
    } do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key", cli_path: mock_script)

      messages =
        session
        |> ClaudeCode.stream("hello")
        |> Enum.to_list()

      # Should contain a result message
      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result != nil
      assert result.result == "Hello there"

      GenServer.stop(session)
    end
  end

  describe "stream interrupted mid-query" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash
      while IFS= read -r line; do
        sleep 30
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"should not see this","session_id":"interrupt-test","total_cost_usd":0.001,"usage":{}}'
      done
      exit 0
      """)
    end

    test "interrupted query terminates stream without result message", %{
      mock_script: mock_script
    } do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key", cli_path: mock_script)

      stream_task =
        Task.async(fn ->
          session
          |> ClaudeCode.stream("slow query")
          |> Enum.to_list()
        end)

      # Wait for query to be sent
      Process.sleep(300)

      # Interrupt
      :ok = ClaudeCode.interrupt(session)

      # Stream should terminate (not hang)
      messages = Task.await(stream_task, 5_000)

      # The stream ended without a result message (interrupted before result arrived)
      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result == nil

      GenServer.stop(session)
    end
  end
end
