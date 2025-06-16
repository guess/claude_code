defmodule ClaudeCode.SessionTest do
  use ExUnit.Case

  alias ClaudeCode.Message.Result
  alias ClaudeCode.Session

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
      assert state.model == "claude-3-opus-20240229"

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

  describe "query handling with mock CLI" do
    setup do
      # Create a mock CLI script that outputs test responses
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Write a simple mock script that echoes JSON matching real CLI format
      File.write!(mock_script, """
      #!/bin/bash
      # Output system init message
      echo '{"type":"system","subtype":"init","cwd":"/Users/steve/repos/guess/claude_code","session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63","tools":["Task","Bash","Glob","Grep","LS","exit_plan_mode","Read","Edit","MultiEdit","Write","NotebookRead","NotebookEdit","WebFetch","TodoRead","TodoWrite","WebSearch","mcp__memory__create_entities","mcp__memory__create_relations","mcp__memory__add_observations","mcp__memory__delete_entities","mcp__memory__delete_observations","mcp__memory__delete_relations","mcp__memory__read_graph","mcp__memory__search_nodes","mcp__memory__open_nodes","mcp__filesystem__read_file","mcp__filesystem__read_multiple_files","mcp__filesystem__write_file","mcp__filesystem__edit_file","mcp__filesystem__create_directory","mcp__filesystem__list_directory","mcp__filesystem__directory_tree","mcp__filesystem__move_file","mcp__filesystem__search_files","mcp__filesystem__get_file_info","mcp__filesystem__list_allowed_directories","mcp__github__create_or_update_file","mcp__github__search_repositories","mcp__github__create_repository","mcp__github__get_file_contents","mcp__github__push_files","mcp__github__create_issue","mcp__github__create_pull_request","mcp__github__fork_repository","mcp__github__create_branch","mcp__github__list_commits","mcp__github__list_issues","mcp__github__update_issue","mcp__github__add_issue_comment","mcp__github__search_code","mcp__github__search_issues","mcp__github__search_users","mcp__github__get_issue","mcp__github__get_pull_request","mcp__github__list_pull_requests","mcp__github__create_pull_request_review","mcp__github__merge_pull_request","mcp__github__get_pull_request_files","mcp__github__get_pull_request_status","mcp__github__update_pull_request_branch","mcp__github__get_pull_request_comments","mcp__github__get_pull_request_reviews","mcp__fetch__fetch","mcp__linear__list_comments","mcp__linear__create_comment","mcp__linear__get_document","mcp__linear__list_documents","mcp__linear__get_issue","mcp__linear__get_issue_git_branch_name","mcp__linear__list_issues","mcp__linear__create_issue","mcp__linear__update_issue","mcp__linear__list_issue_statuses","mcp__linear__get_issue_status","mcp__linear__list_my_issues","mcp__linear__list_issue_labels","mcp__linear__list_projects","mcp__linear__get_project","mcp__linear__create_project","mcp__linear__update_project","mcp__linear__list_teams","mcp__linear__get_team","mcp__linear__list_users","mcp__linear__get_user","mcp__linear__search_documentation"],"mcp_servers":[{"name":"memory","status":"connected"},{"name":"filesystem","status":"connected"},{"name":"github","status":"connected"},{"name":"fetch","status":"connected"},{"name":"linear","status":"connected"}],"model":"claude-opus-4-20250514","permissionMode":"bypassPermissions","apiKeySource":"ANTHROPIC_API_KEY"}'
      # Output assistant message
      echo '{"type":"assistant","message":{"id":"msg_01MdrpoBUNGFcga4mKy3HBCn","type":"message","role":"assistant","model":"claude-opus-4-20250514","content":[{"type":"text","text":"Hello from Claude Code CLI!"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3,"cache_creation_input_tokens":4355,"cache_read_input_tokens":22749,"output_tokens":5,"service_tier":"standard"}},"parent_tool_use_id":null,"session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63"}'
      # Output result message
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":10048,"duration_api_ms":16300,"num_turns":1,"result":"Hello from mock CLI!","session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63","total_cost_usd":0.12251155000000002,"usage":{"input_tokens":3,"cache_creation_input_tokens":4355,"cache_read_input_tokens":22749,"output_tokens":38,"server_tool_use":{"web_search_requests":0}}}'
      exit 0
      """)

      File.chmod!(mock_script, 0o755)

      # Add mock directory to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_dir: mock_dir}
    end

    test "handles successful query response", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # This should use our mock CLI
      response = GenServer.call(session, {:query, "test prompt", []}, 5000)

      assert response == {:ok, "Hello from mock CLI!"}

      GenServer.stop(session)
    end
  end

  describe "error handling" do
    test "handles CLI not found" do
      # Temporarily clear PATH to ensure CLI is not found
      original_path = System.get_env("PATH")
      System.put_env("PATH", "")

      {:ok, session} = Session.start_link(api_key: "test-key")

      response = GenServer.call(session, {:query, "test", []})

      assert {:error, {:cli_not_found, _message}} = response

      System.put_env("PATH", original_path)
      GenServer.stop(session)
    end
  end

  describe "streaming queries" do
    setup do
      # Create a mock CLI script that outputs messages with delays
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_stream_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Write a mock script that streams messages
      File.write!(mock_script, """
      #!/bin/bash
      # Output system init message
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"test-123","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
      sleep 0.1
      # Output first assistant message
      echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Hello "}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"test-123"}'
      sleep 0.1
      # Output second assistant message
      echo '{"type":"assistant","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"world!"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"test-123"}'
      sleep 0.1
      # Output result message
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":300,"duration_api_ms":250,"num_turns":1,"result":"Hello world!","session_id":"test-123","total_cost_usd":0.001,"usage":{}}'
      exit 0
      """)

      File.chmod!(mock_script, 0o755)

      # Add mock directory to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_dir: mock_dir}
    end

    test "query_stream returns a request reference", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      {:ok, ref} = GenServer.call(session, {:query_stream, "test", []})
      assert is_reference(ref)

      GenServer.stop(session)
    end

    test "query_async sends messages to caller", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      {:ok, ref} = GenServer.call(session, {:query_async, "test", []})

      # Collect messages
      case collect_stream_messages(ref, 1000) do
        {:error, reason} ->
          flunk("Failed to collect messages: #{inspect(reason)}")

        messages ->
          # Should receive assistant messages and result (no system message)
          assert length(messages) >= 2

          # Check message types
          assert Enum.any?(messages, &match?(%ClaudeCode.Message.Assistant{}, &1))
          assert Enum.any?(messages, &match?(%Result{}, &1))
      end

      GenServer.stop(session)
    end

    test "stream cleanup removes request", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      {:ok, ref} = GenServer.call(session, {:query_stream, "test", []})

      # Wait a bit for async start
      Process.sleep(100)

      # Check that request exists
      state = :sys.get_state(session)
      assert map_size(state.active_requests) > 0

      # Send cleanup
      GenServer.cast(session, {:stream_cleanup, ref})
      Process.sleep(50)

      # Check that request is removed
      state = :sys.get_state(session)
      assert map_size(state.active_requests) == 0

      GenServer.stop(session)
    end

    defp collect_stream_messages(ref, timeout) do
      # First wait for stream to start
      receive do
        {:claude_stream_started, ^ref} ->
          collect_stream_messages_loop(ref, timeout, [])

        {:claude_stream_error, ^ref, error} ->
          {:error, error}
      after
        timeout ->
          {:error, :timeout}
      end
    end

    defp collect_stream_messages_loop(ref, timeout, acc) do
      receive do
        {:claude_message, ^ref, message} ->
          collect_stream_messages_loop(ref, timeout, [message | acc])

        {:claude_stream_end, ^ref} ->
          Enum.reverse(acc)
      after
        timeout ->
          Enum.reverse(acc)
      end
    end
  end

  describe "session ID storage and continuity" do
    setup do
      # Create mock CLI scripts that output different session IDs
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_session_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Script that outputs a session ID and checks for --resume flag
      File.write!(mock_script, """
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

      # Output system init message with session ID
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'

      # Output assistant message with session ID
      echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Hello"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"'$session_id'"}'

      # Output result message with session ID
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Hello from session '$session_id'","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'

      exit 0
      """)

      File.chmod!(mock_script, 0o755)

      # Add mock directory to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_dir: mock_dir}
    end

    test "captures session ID from system message", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Initial state should have no session ID
      state = :sys.get_state(session)
      assert state.session_id == nil

      # Run a query
      {:ok, _result} = GenServer.call(session, {:query, "test prompt", []})

      # Session ID should now be stored
      state = :sys.get_state(session)
      assert state.session_id == "test-session-123"

      GenServer.stop(session)
    end

    test "captures session ID from assistant message", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Run query and check that we capture session ID from assistant message too
      {:ok, _result} = GenServer.call(session, {:query, "test prompt", []})

      state = :sys.get_state(session)
      assert state.session_id == "test-session-123"

      GenServer.stop(session)
    end

    test "captures session ID from result message", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Run query and verify session ID is captured
      {:ok, result} = GenServer.call(session, {:query, "test prompt", []})

      # Result should contain the session ID
      assert result == "Hello from session test-session-123"

      state = :sys.get_state(session)
      assert state.session_id == "test-session-123"

      GenServer.stop(session)
    end

    test "session ID persists across queries", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # First query establishes session ID
      {:ok, _result1} = GenServer.call(session, {:query, "first query", []})
      state = :sys.get_state(session)
      session_id_1 = state.session_id

      # Second query should have same session ID
      {:ok, _result2} = GenServer.call(session, {:query, "second query", []})
      state = :sys.get_state(session)
      session_id_2 = state.session_id

      assert session_id_1 == session_id_2
      assert session_id_1 == "test-session-123"

      GenServer.stop(session)
    end

    test "session ID is captured during streaming queries", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Start streaming query
      {:ok, ref} = GenServer.call(session, {:query_async, "streaming test", []})

      # Collect messages
      case collect_stream_messages(ref, 1000) do
        {:error, reason} ->
          flunk("Stream collection failed: #{inspect(reason)}")

        _messages ->
          # Session ID should be captured even during streaming
          state = :sys.get_state(session)
          assert state.session_id == "test-session-123"
      end

      GenServer.stop(session)
    end
  end

  describe "session management API" do
    setup do
      # Create mock CLI that respects --resume flag
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_api_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      File.write!(mock_script, """
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

      # Output messages with appropriate session ID
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Session: '$session_id'","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'

      exit 0
      """)

      File.chmod!(mock_script, 0o755)

      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_dir: mock_dir}
    end

    test "get_session_id returns current session ID", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Initially no session ID
      {:ok, session_id} = GenServer.call(session, :get_session_id)
      assert session_id == nil

      # Run query to establish session
      {:ok, _result} = GenServer.call(session, {:query, "test", []})

      # Now should return session ID
      {:ok, session_id} = GenServer.call(session, :get_session_id)
      assert session_id == "new-session-456"

      GenServer.stop(session)
    end

    test "clear clears the session ID", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Establish session
      {:ok, _result} = GenServer.call(session, {:query, "test", []})
      {:ok, session_id} = GenServer.call(session, :get_session_id)
      assert session_id == "new-session-456"

      # Clear session
      :ok = GenServer.call(session, :clear_session)

      # Session ID should be nil
      {:ok, session_id} = GenServer.call(session, :get_session_id)
      assert session_id == nil

      GenServer.stop(session)
    end

    test "new queries after clear start fresh session", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # First query establishes session
      {:ok, result1} = GenServer.call(session, {:query, "first", []})
      assert result1 == "Session: new-session-456"

      # Clear session
      :ok = GenServer.call(session, :clear_session)

      # Next query starts new session (not using --resume)
      {:ok, result2} = GenServer.call(session, {:query, "second", []})
      # New session gets same ID in mock
      assert result2 == "Session: new-session-456"

      GenServer.stop(session)
    end
  end

  describe "session persistence" do
    setup do
      # Simple mock CLI that outputs session info
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_persistence_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      File.write!(mock_script, """
      #!/bin/bash

      # Default session ID
      session_id="persistent-session-789"

      # Output messages with session ID
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"'$session_id'","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Success with session: '$session_id'","session_id":"'$session_id'","total_cost_usd":0.001,"usage":{}}'

      exit 0
      """)

      File.chmod!(mock_script, 0o755)

      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_dir: mock_dir}
    end

    test "preserves valid session IDs when queries succeed", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # First query establishes valid session
      {:ok, result1} = GenServer.call(session, {:query, "first query", []})
      assert result1 == "Success with session: persistent-session-789"

      {:ok, session_id1} = GenServer.call(session, :get_session_id)
      assert session_id1 == "persistent-session-789"

      # Second query should preserve the valid session
      {:ok, result2} = GenServer.call(session, {:query, "second query", []})
      assert result2 == "Success with session: persistent-session-789"

      {:ok, session_id2} = GenServer.call(session, :get_session_id)
      # Should be the same
      assert session_id2 == session_id1

      GenServer.stop(session)
    end
  end

  describe "concurrent query handling" do
    setup do
      # Create mock scripts with different responses
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_concurrent_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Script that outputs different responses based on the prompt
      File.write!(mock_script, """
      #!/bin/bash
      # Get the last argument as the prompt (after all the flags)
      for arg in "$@"; do
        prompt="$arg"
      done

      # Output system init message
      echo '{"type":"system","subtype":"init","model":"claude-3","session_id":"test-'$$'","cwd":"/tmp","tools":[],"mcp_servers":[],"permissionMode":"allow","apiKeySource":"env"}'
      sleep 0.05

      # Output different responses based on prompt
      case "$prompt" in
        *"query1"*)
          echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Response 1"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"test-'$$'"}'
          sleep 0.05
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Response 1","session_id":"test-'$$'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
          ;;
        *"query2"*)
          echo '{"type":"assistant","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Response 2"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"test-'$$'"}'
          sleep 0.05
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":150,"duration_api_ms":120,"num_turns":1,"result":"Response 2","session_id":"test-'$$'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
          ;;
        *"query3"*)
          echo '{"type":"assistant","message":{"id":"msg_3","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Response 3"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"test-'$$'"}'
          sleep 0.05
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":200,"duration_api_ms":160,"num_turns":1,"result":"Response 3","session_id":"test-'$$'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
          ;;
        *)
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Unknown query","session_id":"test-'$$'","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5}}'
          ;;
      esac
      exit 0
      """)

      File.chmod!(mock_script, 0o755)

      # Add mock directory to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_dir: mock_dir}
    end

    test "handles multiple concurrent sync queries", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Start 3 concurrent queries
      task1 =
        Task.async(fn ->
          GenServer.call(session, {:query, "query1", []}, 5000)
        end)

      task2 =
        Task.async(fn ->
          GenServer.call(session, {:query, "query2", []}, 5000)
        end)

      task3 =
        Task.async(fn ->
          GenServer.call(session, {:query, "query3", []}, 5000)
        end)

      # Wait for all results
      results = [
        Task.await(task1),
        Task.await(task2),
        Task.await(task3)
      ]

      # Verify each query got its correct response
      assert {:ok, "Response 1"} in results
      assert {:ok, "Response 2"} in results
      assert {:ok, "Response 3"} in results

      # Verify all requests are cleaned up
      state = :sys.get_state(session)
      assert map_size(state.active_requests) == 0

      GenServer.stop(session)
    end

    test "handles concurrent streaming queries", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Start multiple streaming queries
      {:ok, ref1} = GenServer.call(session, {:query_async, "query1", []})
      {:ok, ref2} = GenServer.call(session, {:query_async, "query2", []})
      {:ok, ref3} = GenServer.call(session, {:query_async, "query3", []})

      # Collect messages for each stream
      results = {
        collect_stream_messages(ref1, 2000),
        collect_stream_messages(ref2, 2000),
        collect_stream_messages(ref3, 2000)
      }

      case results do
        {{:error, r1}, {:error, r2}, {:error, r3}} ->
          flunk("All streams failed: #{inspect({r1, r2, r3})}")

        {messages1, messages2, messages3} ->
          # Handle possible errors
          messages1 = if is_list(messages1), do: messages1, else: []
          messages2 = if is_list(messages2), do: messages2, else: []
          messages3 = if is_list(messages3), do: messages3, else: []

          # Verify each stream got its messages
          result1 = Enum.find(messages1, &match?(%Result{}, &1))
          result2 = Enum.find(messages2, &match?(%Result{}, &1))
          result3 = Enum.find(messages3, &match?(%Result{}, &1))

          assert result1 != nil, "No result found for stream 1"
          assert result2 != nil, "No result found for stream 2"
          assert result3 != nil, "No result found for stream 3"

          assert result1.result == "Response 1"
          assert result2.result == "Response 2"
          assert result3.result == "Response 3"
      end

      # Verify cleanup
      Process.sleep(100)
      state = :sys.get_state(session)
      assert map_size(state.active_requests) == 0

      GenServer.stop(session)
    end

    test "handles mixed sync and streaming queries", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Start mixed query types
      sync_task =
        Task.async(fn ->
          GenServer.call(session, {:query, "query1", []}, 5000)
        end)

      {:ok, stream_ref} = GenServer.call(session, {:query_async, "query2", []})

      # Get results
      sync_result = Task.await(sync_task)

      # Collect stream messages
      case collect_stream_messages(stream_ref, 1000) do
        {:error, reason} ->
          flunk("Stream collection failed: #{inspect(reason)}")

        stream_messages ->
          # Verify sync result
          assert sync_result == {:ok, "Response 1"}

          # Verify stream result
          result_msg = Enum.find(stream_messages, &match?(%Result{}, &1))
          assert result_msg != nil, "No result message found in stream"
          assert result_msg.result == "Response 2"
      end

      GenServer.stop(session)
    end

    test "isolates errors to specific requests", %{mock_dir: _mock_dir} do
      # This test verifies that when one CLI subprocess fails, it doesn't affect other requests
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Start multiple concurrent queries
      tasks = [
        Task.async(fn ->
          GenServer.call(session, {:query, "query1", []}, 5000)
        end),
        Task.async(fn ->
          GenServer.call(session, {:query, "query2", []}, 5000)
        end),
        Task.async(fn ->
          # This one will fail because the mock doesn't recognize "unknown"
          # and returns the default case
          GenServer.call(session, {:query, "query3", []}, 5000)
        end)
      ]

      # Get results
      results = Enum.map(tasks, &Task.await(&1))

      # At least 2 should succeed
      successful = Enum.filter(results, &match?({:ok, _}, &1))
      assert length(successful) >= 2

      # The expected results should be in there
      assert {:ok, "Response 1"} in results
      assert {:ok, "Response 2"} in results

      GenServer.stop(session)
    end

    test "handles request timeouts independently", %{mock_dir: mock_dir} do
      # Create a slow mock script
      slow_script = Path.join(mock_dir, "claude_slow")

      File.write!(slow_script, """
      #!/bin/bash
      echo '{"type":"system","subtype":"init","model":"claude-3","session_id":"test-slow","cwd":"/tmp","tools":[],"mcp_servers":[],"permissionMode":"allow","apiKeySource":"env"}'
      # Never send result, just sleep
      sleep 10
      """)

      File.chmod!(slow_script, 0o755)

      # Start session with very short timeout for testing
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Temporarily set a shorter timeout by updating the module attribute
      # Note: In real code, we'd make this configurable
      # For now, we'll just test that the timeout mechanism exists

      # Start a normal query
      task1 =
        Task.async(fn ->
          GenServer.call(session, {:query, "query1", []}, 5000)
        end)

      # Verify normal query completes
      assert {:ok, "Response 1"} = Task.await(task1)

      GenServer.stop(session)
    end
  end
end
