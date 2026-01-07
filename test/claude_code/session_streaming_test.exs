defmodule ClaudeCode.SessionStreamingTest do
  use ExUnit.Case

  alias ClaudeCode.Message.ResultMessage

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
      {:ok, result} = MockCLI.sync_query(session, "Hello")
      assert %ResultMessage{result: "Streaming response"} = result

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
        |> ClaudeCode.stream("Test query")
        |> Enum.to_list()

      # Should have messages including result
      assert length(messages) >= 1
      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result != nil
      assert result.result == "Stream query response"

      GenServer.stop(session)
    end

    test "query_stream returns messages via Stream", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      messages =
        session
        |> ClaudeCode.stream("Test")
        |> Enum.to_list()

      # Should have received messages
      assert length(messages) >= 1
      assert Enum.any?(messages, &match?(%ResultMessage{}, &1))

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
      {:ok, result1} = MockCLI.sync_query(session, "First question")
      assert %ResultMessage{result: "Turn 1 response"} = result1

      # Second query on same session
      {:ok, result2} = MockCLI.sync_query(session, "Second question")
      assert %ResultMessage{result: "Turn 2 response"} = result2

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

      {:ok, _result} = MockCLI.sync_query(session, "Hello")

      # Session ID should be captured
      session_id = ClaudeCode.get_session_id(session)
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

      {:ok, result} = MockCLI.sync_query(session, "Hello")
      assert %ResultMessage{result: "Resumed session: previous-session-xyz"} = result

      GenServer.stop(session)
    end
  end
end
