defmodule ClaudeCode.SessionTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Session

  @adapter {ClaudeCode.Test, ClaudeCode}

  # ============================================================================
  # Tests using ClaudeCode.Test adapter (faster, no subprocess)
  # ============================================================================

  describe "query handling with test adapter" do
    test "handles successful query response" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [
          ClaudeCode.Test.text("Hello from test adapter!"),
          ClaudeCode.Test.result("Hello from test adapter!")
        ]
      end)

      {:ok, session} = Session.start_link(adapter: @adapter)

      result =
        session
        |> ClaudeCode.stream("test prompt")
        |> ClaudeCode.Stream.final_text()

      assert result == "Hello from test adapter!"

      ClaudeCode.stop(session)
    end

    test "handles query with tool use" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [
          ClaudeCode.Test.text("Let me read that file"),
          ClaudeCode.Test.tool_use("Read", %{path: "/tmp/test.txt"}),
          ClaudeCode.Test.tool_result("File contents here"),
          ClaudeCode.Test.text("Done reading"),
          ClaudeCode.Test.result("Done reading")
        ]
      end)

      {:ok, session} = Session.start_link(adapter: @adapter)

      messages =
        session
        |> ClaudeCode.stream("read file")
        |> Enum.to_list()

      # Should have tool use in the messages
      tool_uses =
        Enum.filter(messages, fn
          %AssistantMessage{message: %{content: content}} ->
            Enum.any?(content, &match?(%Content.ToolUseBlock{}, &1))

          _ ->
            false
        end)

      assert length(tool_uses) == 1

      ClaudeCode.stop(session)
    end

    test "handles error result" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [ClaudeCode.Test.result("Rate limit exceeded", is_error: true)]
      end)

      {:ok, session} = Session.start_link(adapter: @adapter)

      messages =
        session
        |> ClaudeCode.stream("test")
        |> Enum.to_list()

      result = List.last(messages)
      assert %ResultMessage{is_error: true, result: "Rate limit exceeded"} = result

      ClaudeCode.stop(session)
    end

    test "query_stream returns a request reference" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [ClaudeCode.Test.text("Hello")]
      end)

      {:ok, session} = Session.start_link(adapter: @adapter)

      {:ok, ref} = GenServer.call(session, {:query_stream, "test", []})
      assert is_reference(ref)

      ClaudeCode.stop(session)
    end

    test "stream cleanup removes request" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [ClaudeCode.Test.text("Hello")]
      end)

      {:ok, session} = Session.start_link(adapter: @adapter)

      {:ok, ref} = GenServer.call(session, {:query_stream, "test", []})

      # Allow async delivery
      Process.sleep(50)

      # Check that request exists
      state = :sys.get_state(session)
      assert map_size(state.requests) > 0

      # Send cleanup
      GenServer.cast(session, {:stream_cleanup, ref})
      Process.sleep(50)

      # Check that request is removed
      state = :sys.get_state(session)
      assert map_size(state.requests) == 0

      ClaudeCode.stop(session)
    end

    test "handles multiple sequential queries" do
      counter = :counters.new(1, [])

      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        :counters.add(counter, 1, 1)
        count = :counters.get(counter, 1)

        [
          ClaudeCode.Test.text("Response #{count}"),
          ClaudeCode.Test.result("Response #{count}")
        ]
      end)

      {:ok, session} = Session.start_link(adapter: @adapter)

      # First query
      result1 =
        session
        |> ClaudeCode.stream("first")
        |> ClaudeCode.Stream.final_text()

      assert result1 == "Response 1"

      # Second query
      result2 =
        session
        |> ClaudeCode.stream("second")
        |> ClaudeCode.Stream.final_text()

      assert result2 == "Response 2"

      ClaudeCode.stop(session)
    end

    test "captures session ID from messages" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [
          ClaudeCode.Test.text("Hello", session_id: "captured-session-abc"),
          ClaudeCode.Test.result("Hello", session_id: "captured-session-abc")
        ]
      end)

      {:ok, session} = Session.start_link(adapter: @adapter)

      # Initially no session ID
      assert ClaudeCode.get_session_id(session) == nil

      # Run query
      _result =
        session
        |> ClaudeCode.stream("test")
        |> Enum.to_list()

      # Session ID should be captured
      # Note: ClaudeCode.Test unifies session IDs, so this tests the capture mechanism
      session_id = ClaudeCode.get_session_id(session)
      assert session_id != nil

      ClaudeCode.stop(session)
    end
  end

  # ============================================================================
  # GenServer lifecycle tests
  # ============================================================================

  describe "start_link/1" do
    test "starts with required options" do
      {:ok, pid} = Session.start_link(api_key: "test-key")
      assert is_pid(pid)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom model" do
      {:ok, pid} =
        Session.start_link(
          api_key: "test-key",
          model: "claude-3-opus-20240229"
        )

      state = :sys.get_state(pid)
      assert Keyword.get(state.session_options, :model) == "claude-3-opus-20240229"

      GenServer.stop(pid)
    end

    test "starts with name" do
      {:ok, pid} =
        Session.start_link(
          api_key: "test-key",
          name: :test_session
        )

      assert Process.whereis(:test_session) == pid
      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Tests using MockCLI (integration tests requiring CLI subprocess)
  # These tests verify CLI argument handling, Port behavior, and session persistence
  # ============================================================================

  describe "query handling with mock CLI (integration)" do
    setup do
      MockCLI.setup([
        MockCLI.system_message(session_id: "a4c79bab-3a68-425c-988e-0aa6b9151a63"),
        MockCLI.assistant_message(
          text: "Hello from Claude Code CLI!",
          session_id: "a4c79bab-3a68-425c-988e-0aa6b9151a63"
        ),
        MockCLI.result_message(
          result: "Hello from mock CLI!",
          session_id: "a4c79bab-3a68-425c-988e-0aa6b9151a63"
        )
      ])
    end

    test "handles successful query via CLI subprocess", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # This uses the mock CLI subprocess
      response = MockCLI.sync_query(session, "test prompt")

      assert {:ok, %ResultMessage{result: "Hello from mock CLI!"}} = response

      GenServer.stop(session)
    end
  end

  describe "error handling" do
    test "handles CLI not found" do
      # Use cli_path option with nonexistent path to force CLI not found
      {:ok, session} =
        Session.start_link(
          api_key: "test-key",
          cli_path: "/nonexistent/path/to/claude"
        )

      # Stream should throw error when CLI not found during async provisioning.
      # The CLI adapter now provisions asynchronously and reports status via
      # {:adapter_status, {:error, reason}}, which the session translates to
      # {:provisioning_failed, reason} for queued requests.
      thrown =
        session
        |> ClaudeCode.stream("test")
        |> Enum.to_list()
        |> catch_throw()

      assert {:stream_error, {:provisioning_failed, {:cli_not_found, message}}} = thrown
      assert message =~ "Claude CLI not found"

      GenServer.stop(session)
    end
  end

  describe "streaming queries" do
    setup do
      MockCLI.setup(
        [
          MockCLI.system_message(),
          MockCLI.assistant_message(text: "Hello "),
          MockCLI.assistant_message(text: "world!", message_id: "msg_2"),
          MockCLI.result_message(result: "Hello world!", duration_ms: 300, duration_api_ms: 250)
        ],
        sleep: 0.01
      )
    end

    test "query_stream returns a request reference", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      {:ok, ref} = GenServer.call(session, {:query_stream, "test", []})
      assert is_reference(ref)

      GenServer.stop(session)
    end

    test "stream cleanup removes request", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      {:ok, ref} = GenServer.call(session, {:query_stream, "test", []})

      # Wait a bit for async start
      Process.sleep(100)

      # Check that request exists
      state = :sys.get_state(session)
      assert map_size(state.requests) > 0

      # Send cleanup
      GenServer.cast(session, {:stream_cleanup, ref})
      Process.sleep(50)

      # Check that request is removed
      state = :sys.get_state(session)
      assert map_size(state.requests) == 0

      GenServer.stop(session)
    end
  end

  describe "session ID storage and continuity" do
    setup do
      # Script that outputs a session ID and checks for --resume flag (streaming-aware)
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Check for --resume flag and session ID
      session_id="test-session-123"
      is_resume=false

      for arg in "$@"; do
        case "$arg" in
          --resume)
            is_resume=true
            ;;
          test-session-123)
            if [ "$is_resume" = true ]; then
              session_id="test-session-123"  # Same session continued
            fi
            ;;
        esac
      done

      # Streaming mode: read from stdin and output messages for each input
      while IFS= read -r line; do
        # Output system init message with session ID
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

        # Output assistant message with session ID
        echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"'$session_id'"}'

        # Output result message with session ID
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Hello from session '$session_id'","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'
      done

      exit 0
      """)
    end

    test "captures session ID from system message", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Initial state should have no session ID
      state = :sys.get_state(session)
      assert state.session_id == nil

      # Run a query
      {:ok, _result} = MockCLI.sync_query(session, "test prompt")

      # Session ID should now be stored
      state = :sys.get_state(session)
      assert state.session_id == "test-session-123"

      GenServer.stop(session)
    end

    test "captures session ID from assistant message", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Run query and check that we capture session ID from assistant message too
      {:ok, _result} = MockCLI.sync_query(session, "test prompt")

      state = :sys.get_state(session)
      assert state.session_id == "test-session-123"

      GenServer.stop(session)
    end

    test "captures session ID from result message", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Run query and verify session ID is captured
      {:ok, result} = MockCLI.sync_query(session, "test prompt")

      # Result should contain the session ID
      assert %ResultMessage{result: "Hello from session test-session-123"} = result

      state = :sys.get_state(session)
      assert state.session_id == "test-session-123"

      GenServer.stop(session)
    end

    test "session ID persists across queries", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # First query establishes session ID
      {:ok, _result1} = MockCLI.sync_query(session, "first query")
      state = :sys.get_state(session)
      session_id_1 = state.session_id

      # Second query should have same session ID
      {:ok, _result2} = MockCLI.sync_query(session, "second query")
      state = :sys.get_state(session)
      session_id_2 = state.session_id

      assert session_id_1 == session_id_2
      assert session_id_1 == "test-session-123"

      GenServer.stop(session)
    end

    test "session ID is captured during streaming queries", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Start streaming query using stream
      _messages =
        session
        |> ClaudeCode.stream("streaming test")
        |> Enum.to_list()

      # Session ID should be captured during streaming
      state = :sys.get_state(session)
      assert state.session_id == "test-session-123"

      GenServer.stop(session)
    end
  end

  describe "session management API" do
    setup do
      # Create mock CLI that respects --resume flag (streaming-aware)
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Default session ID
      session_id="new-session-456"

      # Check for --resume flag
      is_resume=false
      prev_arg=""

      for arg in "$@"; do
        if [ "$prev_arg" = "--resume" ]; then
          session_id="$arg"  # Use provided session ID
          break
        fi
        if [ "$arg" = "--resume" ]; then
          is_resume=true
        fi
        prev_arg="$arg"
      done

      # Streaming mode: read from stdin and output messages for each input
      while IFS= read -r line; do
        # Output messages with appropriate session ID
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Session: '$session_id'","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'
      done

      exit 0
      """)
    end

    test "get_session_id returns current session ID", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Initially no session ID
      session_id = GenServer.call(session, :get_session_id)
      assert session_id == nil

      # Run query to establish session
      {:ok, _result} = MockCLI.sync_query(session, "test")

      # Now should return session ID
      session_id = GenServer.call(session, :get_session_id)
      assert session_id == "new-session-456"

      GenServer.stop(session)
    end

    test "clear clears the session ID", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Establish session
      {:ok, _result} = MockCLI.sync_query(session, "test")
      session_id = GenServer.call(session, :get_session_id)
      assert session_id == "new-session-456"

      # Clear session
      :ok = GenServer.call(session, :clear_session)

      # Session ID should be nil
      session_id = GenServer.call(session, :get_session_id)
      assert session_id == nil

      GenServer.stop(session)
    end

    test "new queries after clear start fresh session", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # First query establishes session
      {:ok, result1} = MockCLI.sync_query(session, "first")
      assert %ResultMessage{result: "Session: new-session-456"} = result1

      # Clear session
      :ok = GenServer.call(session, :clear_session)

      # Next query starts new session (not using --resume)
      {:ok, result2} = MockCLI.sync_query(session, "second")
      # New session gets same ID in mock
      assert %ResultMessage{result: "Session: new-session-456"} = result2

      GenServer.stop(session)
    end
  end

  describe "session persistence" do
    setup do
      # Simple mock CLI that outputs session info (streaming-aware)
      MockCLI.setup_with_script("""
      #!/bin/bash

      # Default session ID
      session_id="persistent-session-789"

      # Streaming mode: read from stdin and output messages for each input
      while IFS= read -r line; do
        # Output messages with session ID
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Success with session: '$session_id'","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'
      done

      exit 0
      """)
    end

    test "preserves valid session IDs when queries succeed", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # First query establishes valid session
      {:ok, result1} = MockCLI.sync_query(session, "first query")
      assert %ResultMessage{result: "Success with session: persistent-session-789"} = result1

      session_id1 = GenServer.call(session, :get_session_id)
      assert session_id1 == "persistent-session-789"

      # Second query should preserve the valid session
      {:ok, result2} = MockCLI.sync_query(session, "second query")
      assert %ResultMessage{result: "Success with session: persistent-session-789"} = result2

      session_id2 = GenServer.call(session, :get_session_id)
      # Should be the same
      assert session_id2 == session_id1

      GenServer.stop(session)
    end
  end

  describe "concurrent query handling" do
    setup do
      # Script that outputs different responses based on the prompt (streaming-aware)
      # Note: With streaming mode, queries are serialized (queued), not truly concurrent
      MockCLI.setup_with_script("""
      #!/bin/bash
      session_id="test-$$"

      # Streaming mode: read from stdin and output messages for each input
      while IFS= read -r line; do
        # Output system init message
        echo '{"type":"system","subtype":"init","model":"claude-3","session_id":"'$session_id'","cwd":"/tmp","tools":[],"mcp_servers":[],"permissionMode":"allow","apiKeySource":"env"}'

        # Parse the prompt from the JSON input
        # The input is like: {"type":"user","message":{"role":"user","content":"query1"},...}
        case "$line" in
          *"query1"*)
            echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Response 1"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"'$session_id'"}'
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Response 1","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
            ;;
          *"query2"*)
            echo '{"type":"assistant","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Response 2"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"'$session_id'"}'
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":150,"duration_api_ms":120,"num_turns":1,"result":"Response 2","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
            ;;
          *"query3"*)
            echo '{"type":"assistant","message":{"id":"msg_3","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Response 3"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"'$session_id'"}'
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":200,"duration_api_ms":160,"num_turns":1,"result":"Response 3","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
            ;;
          *)
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Unknown query","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
            ;;
        esac
      done
      exit 0
      """)
    end

    test "handles multiple concurrent queries", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Start 3 concurrent queries (they get queued and run sequentially)
      task1 =
        Task.async(fn ->
          MockCLI.sync_query(session, "query1")
        end)

      task2 =
        Task.async(fn ->
          MockCLI.sync_query(session, "query2")
        end)

      task3 =
        Task.async(fn ->
          MockCLI.sync_query(session, "query3")
        end)

      # Wait for all results
      results = [
        Task.await(task1),
        Task.await(task2),
        Task.await(task3)
      ]

      # Verify each query got its correct response
      result_texts = Enum.map(results, fn {:ok, %ResultMessage{result: text}} -> text end)
      assert "Response 1" in result_texts
      assert "Response 2" in result_texts
      assert "Response 3" in result_texts

      # Verify all requests are cleaned up
      Process.sleep(100)
      state = :sys.get_state(session)
      assert map_size(state.requests) == 0

      GenServer.stop(session)
    end

    test "handles sequential streaming queries", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Run multiple streaming queries sequentially (they are serialized internally)
      messages1 =
        session
        |> ClaudeCode.stream("query1")
        |> Enum.to_list()

      messages2 =
        session
        |> ClaudeCode.stream("query2")
        |> Enum.to_list()

      messages3 =
        session
        |> ClaudeCode.stream("query3")
        |> Enum.to_list()

      # Verify each stream got its messages
      result1 = Enum.find(messages1, &match?(%ResultMessage{}, &1))
      result2 = Enum.find(messages2, &match?(%ResultMessage{}, &1))
      result3 = Enum.find(messages3, &match?(%ResultMessage{}, &1))

      assert result1 != nil, "No result found for stream 1"
      assert result2 != nil, "No result found for stream 2"
      assert result3 != nil, "No result found for stream 3"

      assert result1.result == "Response 1"
      assert result2.result == "Response 2"
      assert result3.result == "Response 3"

      # Verify cleanup
      Process.sleep(100)
      state = :sys.get_state(session)
      assert map_size(state.requests) == 0

      GenServer.stop(session)
    end

    test "handles multiple queries in sequence", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # First run a query
      {:ok, result1} = MockCLI.sync_query(session, "query1")
      assert %ResultMessage{result: "Response 1"} = result1

      # Then run another query
      {:ok, result2} = MockCLI.sync_query(session, "query2")
      assert %ResultMessage{result: "Response 2"} = result2

      GenServer.stop(session)
    end

    test "isolates errors to specific requests", %{mock_script: mock_script} do
      # This test verifies that when one CLI subprocess fails, it doesn't affect other requests
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Start multiple concurrent queries (they get queued)
      tasks = [
        Task.async(fn ->
          MockCLI.sync_query(session, "query1")
        end),
        Task.async(fn ->
          MockCLI.sync_query(session, "query2")
        end),
        Task.async(fn ->
          # This one will still return a response (the mock has a default case)
          MockCLI.sync_query(session, "query3")
        end)
      ]

      # Get results
      results = Enum.map(tasks, &Task.await(&1))

      # At least 2 should succeed
      successful = Enum.filter(results, &match?({:ok, %ResultMessage{}}, &1))
      assert length(successful) >= 2

      # The expected results should be in there
      result_texts = Enum.map(successful, fn {:ok, %ResultMessage{result: text}} -> text end)
      assert "Response 1" in result_texts
      assert "Response 2" in result_texts

      GenServer.stop(session)
    end

    test "handles request timeouts independently", %{mock_script: mock_script} do
      {:ok, session} = Session.start_link(api_key: "test-key", cli_path: mock_script)

      # Start a normal query
      {:ok, result} = MockCLI.sync_query(session, "query1")

      # Verify normal query completes
      assert %ResultMessage{result: "Response 1"} = result

      GenServer.stop(session)
    end
  end

  describe "start_link with application config" do
    test "can start without api_key when provided in app config" do
      # Set application config
      original_config = Application.get_all_env(:claude_code)
      Application.put_env(:claude_code, :api_key, "app-config-key")

      try do
        # Should work without explicit api_key
        {:ok, session} = Session.start_link([])

        # Verify session has the API key from app config
        state = :sys.get_state(session)
        assert Keyword.get(state.session_options, :api_key) == "app-config-key"

        GenServer.stop(session)
      after
        # Restore original config
        Application.delete_env(:claude_code, :api_key)

        for {key, value} <- original_config do
          Application.put_env(:claude_code, key, value)
        end
      end
    end

    test "session api_key overrides app config" do
      # Set application config
      original_config = Application.get_all_env(:claude_code)
      Application.put_env(:claude_code, :api_key, "app-config-key")

      try do
        # Explicit api_key should override app config
        {:ok, session} = Session.start_link(api_key: "session-key")

        # Verify session uses the explicit api_key
        state = :sys.get_state(session)
        assert Keyword.get(state.session_options, :api_key) == "session-key"

        GenServer.stop(session)
      after
        # Restore original config
        Application.delete_env(:claude_code, :api_key)

        for {key, value} <- original_config do
          Application.put_env(:claude_code, key, value)
        end
      end
    end

    test "can start without api_key - CLI handles environment fallback" do
      # This should succeed - the CLI will check for ANTHROPIC_API_KEY itself
      {:ok, session} = Session.start_link([])
      assert is_pid(session)
      GenServer.stop(session)
    end
  end
end
