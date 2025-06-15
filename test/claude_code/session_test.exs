defmodule ClaudeCode.SessionTest do
  use ExUnit.Case

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
      response = GenServer.call(session, {:query_sync, "test prompt", []}, 5000)

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

      response = GenServer.call(session, {:query_sync, "test", []})

      assert {:error, {:cli_not_found, _message}} = response

      System.put_env("PATH", original_path)
      GenServer.stop(session)
    end
  end

  describe "message processing" do
    test "processes assistant messages correctly" do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Simulate receiving data from the port
      state = :sys.get_state(session)

      # Add a pending request
      from = {self(), make_ref()}
      request_id = make_ref()

      _state = %{
        state
        | pending_requests: %{
            request_id => %{from: from, buffer: "", messages: []}
          }
      }

      # Send a mock message through the session
      json_line = ~s({"type": "assistant", "message": {"content": [{"text": "Test response", "type": "text"}]}}\n)

      # We need to simulate the port message
      send(session, {nil, {:data, json_line}})

      # Wait a bit for processing
      Process.sleep(100)

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
      messages = collect_stream_messages(ref, 1000)

      # Should receive assistant messages and result (no system message)
      assert length(messages) >= 3

      # Check message types
      assert Enum.any?(messages, &match?(%ClaudeCode.Message.Assistant{}, &1))
      assert Enum.any?(messages, &match?(%ClaudeCode.Message.Result{}, &1))

      GenServer.stop(session)
    end

    test "stream cleanup removes request", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      {:ok, ref} = GenServer.call(session, {:query_stream, "test", []})

      # Check that streaming request exists
      state = :sys.get_state(session)
      assert Map.has_key?(state.streaming_requests, ref)

      # Send cleanup
      GenServer.cast(session, {:stream_cleanup, ref})
      Process.sleep(50)

      # Check that request is removed
      state = :sys.get_state(session)
      refute Map.has_key?(state.streaming_requests, ref)

      GenServer.stop(session)
    end

    defp collect_stream_messages(ref, timeout) do
      collect_stream_messages(ref, timeout, [])
    end

    defp collect_stream_messages(ref, timeout, acc) do
      receive do
        {:claude_message, ^ref, message} ->
          collect_stream_messages(ref, timeout, [message | acc])

        {:claude_stream_end, ^ref} ->
          Enum.reverse(acc)
      after
        timeout ->
          Enum.reverse(acc)
      end
    end
  end
end
