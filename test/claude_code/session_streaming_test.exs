defmodule ClaudeCode.SessionStreamingTest do
  use ExUnit.Case

  alias ClaudeCode.Message.Assistant
  alias ClaudeCode.Message.Result

  describe "streaming mode - connect/2" do
    setup do
      # Create a mock CLI that handles --input-format stream-json
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Check if we're in streaming input mode
      streaming=false
      for arg in "$@"; do
        if [ "$arg" = "stream-json" ]; then
          streaming=true
        fi
      done

      if [ "$streaming" = true ]; then
        # Output system init message
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"streaming-session-123","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

        # Read from stdin and respond to each message
        while IFS= read -r line; do
          # Check if it's a user message
          if echo "$line" | grep -q '"type":"user"'; then
            # Output assistant response
            echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Streaming response"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"streaming-session-123"}'
            # Output result
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Streaming response","session_id":"streaming-session-123","total_cost_usd":0.001,"usage":{}}'
          fi
        done
      else
        # Non-streaming mode (for fallback)
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"regular-123","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Regular response","session_id":"regular-123","total_cost_usd":0.001,"usage":{}}'
      fi

      exit 0
      """)
    end

    test "connect starts streaming CLI process", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      assert :ok = ClaudeCode.connect(session)

      # Verify streaming port is set
      state = :sys.get_state(session)
      assert state.streaming_port != nil

      ClaudeCode.disconnect(session)
      GenServer.stop(session)
    end

    test "connect returns error when already connected", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      :ok = ClaudeCode.connect(session)
      assert {:error, :already_connected} = ClaudeCode.connect(session)

      ClaudeCode.disconnect(session)
      GenServer.stop(session)
    end

    test "disconnect closes streaming connection", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      :ok = ClaudeCode.connect(session)
      :ok = ClaudeCode.disconnect(session)

      # Verify streaming port is cleared
      state = :sys.get_state(session)
      assert state.streaming_port == nil

      GenServer.stop(session)
    end

    test "disconnect returns error when not connected", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      assert {:error, :not_connected} = ClaudeCode.disconnect(session)

      GenServer.stop(session)
    end
  end

  describe "streaming mode - stream_query/2" do
    setup do
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Output system init message
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"stream-query-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      # Read from stdin and respond
      while IFS= read -r line; do
        if echo "$line" | grep -q '"type":"user"'; then
          sleep 0.05
          echo '{"type":"assistant","message":{"id":"msg_s1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Stream query response"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"stream-query-session"}'
          sleep 0.05
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Stream query response","session_id":"stream-query-session","total_cost_usd":0.001,"usage":{}}'
        fi
      done

      exit 0
      """)
    end

    test "stream_query returns error when not connected", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      assert {:error, :not_connected} = ClaudeCode.stream_query(session, "Hello")

      GenServer.stop(session)
    end

    test "stream_query returns request reference when connected", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      :ok = ClaudeCode.connect(session)

      {:ok, req_ref} = ClaudeCode.stream_query(session, "Hello")
      assert is_reference(req_ref)

      ClaudeCode.disconnect(session)
      GenServer.stop(session)
    end

    test "stream_query sends message to streaming CLI", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      :ok = ClaudeCode.connect(session)

      {:ok, req_ref} = ClaudeCode.stream_query(session, "What is 2+2?")

      # Collect messages
      messages =
        session
        |> ClaudeCode.receive_response(req_ref)
        |> Enum.to_list()

      # Should have system, assistant, and result messages
      assert length(messages) >= 1

      ClaudeCode.disconnect(session)
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
      :ok = ClaudeCode.connect(session)

      {:ok, req_ref} = ClaudeCode.stream_query(session, "Test")

      messages =
        session
        |> ClaudeCode.receive_messages(req_ref)
        |> Stream.take_while(fn msg ->
          # Stop after result
          not match?(%Result{}, msg)
        end)
        |> Enum.to_list()

      # Should receive assistant messages (system is filtered)
      assistant_messages = Enum.filter(messages, &match?(%Assistant{}, &1))
      assert length(assistant_messages) >= 1

      ClaudeCode.disconnect(session)
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
      :ok = ClaudeCode.connect(session)

      {:ok, req_ref} = ClaudeCode.stream_query(session, "Test")

      messages =
        session
        |> ClaudeCode.receive_response(req_ref)
        |> Enum.to_list()

      # Should include the result message
      result = Enum.find(messages, &match?(%Result{}, &1))
      assert result != nil
      assert result.result == "Response text"

      ClaudeCode.disconnect(session)
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

    test "supports multiple queries on same connection", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      :ok = ClaudeCode.connect(session)

      # First query
      {:ok, ref1} = ClaudeCode.stream_query(session, "First question")

      messages1 =
        session
        |> ClaudeCode.receive_response(ref1)
        |> Enum.to_list()

      result1 = Enum.find(messages1, &match?(%Result{}, &1))
      assert result1.result == "Turn 1 response"

      # Second query on same connection
      {:ok, ref2} = ClaudeCode.stream_query(session, "Second question")

      messages2 =
        session
        |> ClaudeCode.receive_response(ref2)
        |> Enum.to_list()

      result2 = Enum.find(messages2, &match?(%Result{}, &1))
      assert result2.result == "Turn 2 response"

      ClaudeCode.disconnect(session)
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
      :ok = ClaudeCode.connect(session)

      {:ok, req_ref} = ClaudeCode.stream_query(session, "Hello")

      _messages =
        session
        |> ClaudeCode.receive_response(req_ref)
        |> Enum.to_list()

      # Session ID should be captured
      state = :sys.get_state(session)
      assert state.streaming_session_id == "captured-session-id-abc"

      ClaudeCode.disconnect(session)
      GenServer.stop(session)
    end
  end

  describe "streaming mode - connect with resume" do
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

    test "connect with resume option uses --resume flag", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      :ok = ClaudeCode.connect(session, resume: "previous-session-xyz")

      {:ok, req_ref} = ClaudeCode.stream_query(session, "Hello")

      messages =
        session
        |> ClaudeCode.receive_response(req_ref)
        |> Enum.to_list()

      result = Enum.find(messages, &match?(%Result{}, &1))
      assert result.result == "Resumed session: previous-session-xyz"

      ClaudeCode.disconnect(session)
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

    test "interrupt returns error when not connected", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      ref = make_ref()
      assert {:error, :not_connected} = ClaudeCode.interrupt(session, ref)

      GenServer.stop(session)
    end

    test "interrupt stops streaming request", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      :ok = ClaudeCode.connect(session)

      {:ok, req_ref} = ClaudeCode.stream_query(session, "Long task")

      # Let some messages come in
      Process.sleep(150)

      # Interrupt should return :ok
      assert :ok = ClaudeCode.interrupt(session, req_ref)

      ClaudeCode.disconnect(session)
      GenServer.stop(session)
    end
  end
end
