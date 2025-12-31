defmodule ClaudeCode.SessionStreamingTest do
  use ExUnit.Case

  alias ClaudeCode.Message.Assistant
  alias ClaudeCode.Message.Result

  describe "streaming mode - auto-connect behavior" do
    setup do
      # Create a mock CLI that handles --input-format stream-json
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Output system init message
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"streaming-session-123","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      # Read from stdin and respond to each message
      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          # Output assistant response
          echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Streaming response"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"streaming-session-123"}'
          # Output result
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Streaming response","session_id":"streaming-session-123","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "session connects automatically on first query", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      # Port should be nil initially (lazy connect)
      state = :sys.get_state(session)
      assert state.port == nil

      # First query triggers connection
      {:ok, result} = ClaudeCode.query(session, "Hello")
      assert result == "Streaming response"

      # Port should now be set
      state = :sys.get_state(session)
      assert state.port != nil

      GenServer.stop(session)
    end
  end

  describe "streaming mode - query methods" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"stream-query-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          sleep 0.02
          echo '{"type":"assistant","message":{"id":"msg_s1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Stream query response"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"stream-query-session"}'
          sleep 0.02
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Stream query response","session_id":"stream-query-session","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "query_stream returns a stream of messages", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      messages =
        session
        |> ClaudeCode.query_stream("Test query")
        |> Enum.to_list()

      # Should have messages including result
      assert length(messages) >= 1
      result = Enum.find(messages, &match?(%Result{}, &1))
      assert result != nil
      assert result.result == "Stream query response"

      GenServer.stop(session)
    end

    test "query_async sends messages to caller process", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      {:ok, ref} = ClaudeCode.query_async(session, "Test")

      # Wait for started message
      assert_receive {:claude_stream_started, ^ref}, 1000

      # Collect all messages
      messages = collect_async_messages(ref, [])

      # Should have received messages
      assert length(messages) >= 1
      assert Enum.any?(messages, &match?(%Result{}, &1))

      GenServer.stop(session)
    end
  end

  describe "streaming mode - receive_messages/2" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"recv-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          echo '{"type":"assistant","message":{"id":"msg_r1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Message 1"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"recv-session"}'
          sleep 0.02
          echo '{"type":"assistant","message":{"id":"msg_r2","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Message 2"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"recv-session"}'
          sleep 0.02
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Complete","session_id":"recv-session","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "receive_messages returns stream of all messages", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      {:ok, req_ref} = GenServer.call(session, {:query_stream, "Test", []})

      messages =
        session
        |> ClaudeCode.receive_messages(req_ref)
        |> Stream.take_while(fn msg ->
          not match?(%Result{}, msg)
        end)
        |> Enum.to_list()

      # Should receive assistant messages
      assistant_messages = Enum.filter(messages, &match?(%Assistant{}, &1))
      assert length(assistant_messages) >= 1

      GenServer.stop(session)
    end
  end

  describe "streaming mode - receive_response/2" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"resp-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          echo '{"type":"assistant","message":{"id":"msg_resp1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Response text"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"resp-session"}'
          sleep 0.02
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Response text","session_id":"resp-session","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "receive_response stops at result message", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      {:ok, req_ref} = GenServer.call(session, {:query_stream, "Test", []})

      messages =
        session
        |> ClaudeCode.receive_response(req_ref)
        |> Enum.to_list()

      # Should include the result message
      result = Enum.find(messages, &match?(%Result{}, &1))
      assert result != nil
      assert result.result == "Response text"

      GenServer.stop(session)
    end
  end

  describe "streaming mode - multi-turn conversations" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      turn=0

      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"multi-turn-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          turn=$((turn + 1))
          echo '{"type":"assistant","message":{"id":"msg_turn_'$turn'","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Turn '$turn' response"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"multi-turn-session"}'
          sleep 0.02
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":'$turn',"result":"Turn '$turn' response","session_id":"multi-turn-session","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "supports multiple queries on same session", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      # First query
      {:ok, result1} = ClaudeCode.query(session, "First question")
      assert result1 == "Turn 1 response"

      # Second query on same session
      {:ok, result2} = ClaudeCode.query(session, "Second question")
      assert result2 == "Turn 2 response"

      GenServer.stop(session)
    end
  end

  describe "streaming mode - session ID tracking" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      session_id="captured-session-id-abc"

      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"'$session_id'"}'
          sleep 0.02
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Hello","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "captures session ID from streaming response", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      {:ok, _result} = ClaudeCode.query(session, "Hello")

      # Session ID should be captured
      {:ok, session_id} = ClaudeCode.get_session_id(session)
      assert session_id == "captured-session-id-abc"

      GenServer.stop(session)
    end
  end

  describe "streaming mode - resume option" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Check for --resume flag
      resume_id=""
      prev_arg=""

      for arg in "$@"; do
        if [ "$prev_arg" = "--resume" ]; then
          resume_id="$arg"
          break
        fi
        prev_arg="$arg"
      done

      if [ -n "$resume_id" ]; then
        session_id="$resume_id"
      else
        session_id="new-streaming-session"
      fi

      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Resumed session: '$session_id'"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"'$session_id'"}'
          sleep 0.02
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Resumed session: '$session_id'","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "resume option uses --resume flag", %{mock_dir: _mock_dir} do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          resume: "previous-session-xyz"
        )

      {:ok, result} = ClaudeCode.query(session, "Hello")
      assert result == "Resumed session: previous-session-xyz"

      GenServer.stop(session)
    end
  end

  describe "streaming mode - interrupt/2" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Handle SIGINT for interrupt
      trap 'echo "interrupted"; exit 0' INT

      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"interrupt-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          # Simulate slow response
          for i in 1 2 3 4 5; do
            echo '{"type":"assistant","message":{"id":"msg_slow_'$i'","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Chunk '$i'"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"interrupt-session"}'
            sleep 0.1
          done
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":500,"duration_api_ms":400,"num_turns":1,"result":"Completed","session_id":"interrupt-session","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "interrupt sends signal to CLI", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      {:ok, req_ref} = ClaudeCode.query_async(session, "Long task")

      # Wait for started
      assert_receive {:claude_stream_started, ^req_ref}, 1000

      # Let some messages come in
      Process.sleep(150)

      # Interrupt should return :ok
      assert :ok = ClaudeCode.interrupt(session, req_ref)

      GenServer.stop(session)
    end
  end

  # Helper functions

  defp collect_async_messages(ref, acc) do
    receive do
      {:claude_message, ^ref, message} ->
        collect_async_messages(ref, [message | acc])

      {:claude_stream_end, ^ref} ->
        Enum.reverse(acc)

      {:claude_stream_error, ^ref, _error} ->
        Enum.reverse(acc)
    after
      1000 ->
        Enum.reverse(acc)
    end
  end
end
