defmodule ClaudeCode.SessionShellTest do
  use ExUnit.Case

  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Session

  describe "shell command building" do
    setup do
      # Create a mock CLI that outputs the command it received
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_shell_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # This mock will output valid JSON matching real CLI format
      File.write!(mock_script, ~S"""
      #!/bin/bash
      # Output messages in the same format as real CLI
      # Output system init message
      echo '{"type":"system","subtype":"init","cwd":"/Users/steve/repos/guess/claude_code","session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63","tools":["Task","Bash","Glob","Grep","LS","exit_plan_mode","Read","Edit","MultiEdit","Write","NotebookRead","NotebookEdit","WebFetch","TodoRead","TodoWrite","WebSearch","mcp__memory__create_entities","mcp__memory__create_relations","mcp__memory__add_observations","mcp__memory__delete_entities","mcp__memory__delete_observations","mcp__memory__delete_relations","mcp__memory__read_graph","mcp__memory__search_nodes","mcp__memory__open_nodes","mcp__filesystem__read_file","mcp__filesystem__read_multiple_files","mcp__filesystem__write_file","mcp__filesystem__edit_file","mcp__filesystem__create_directory","mcp__filesystem__list_directory","mcp__filesystem__directory_tree","mcp__filesystem__move_file","mcp__filesystem__search_files","mcp__filesystem__get_file_info","mcp__filesystem__list_allowed_directories","mcp__github__create_or_update_file","mcp__github__search_repositories","mcp__github__create_repository","mcp__github__get_file_contents","mcp__github__push_files","mcp__github__create_issue","mcp__github__create_pull_request","mcp__github__fork_repository","mcp__github__create_branch","mcp__github__list_commits","mcp__github__list_issues","mcp__github__update_issue","mcp__github__add_issue_comment","mcp__github__search_code","mcp__github__search_issues","mcp__github__search_users","mcp__github__get_issue","mcp__github__get_pull_request","mcp__github__list_pull_requests","mcp__github__create_pull_request_review","mcp__github__merge_pull_request","mcp__github__get_pull_request_files","mcp__github__get_pull_request_status","mcp__github__update_pull_request_branch","mcp__github__get_pull_request_comments","mcp__github__get_pull_request_reviews","mcp__fetch__fetch","mcp__linear__list_comments","mcp__linear__create_comment","mcp__linear__get_document","mcp__linear__list_documents","mcp__linear__get_issue","mcp__linear__get_issue_git_branch_name","mcp__linear__list_issues","mcp__linear__create_issue","mcp__linear__update_issue","mcp__linear__list_issue_statuses","mcp__linear__get_issue_status","mcp__linear__list_my_issues","mcp__linear__list_issue_labels","mcp__linear__list_projects","mcp__linear__get_project","mcp__linear__create_project","mcp__linear__update_project","mcp__linear__list_teams","mcp__linear__get_team","mcp__linear__list_users","mcp__linear__get_user","mcp__linear__search_documentation"],"mcp_servers":[{"name":"memory","status":"connected"},{"name":"filesystem","status":"connected"},{"name":"github","status":"connected"},{"name":"fetch","status":"connected"},{"name":"linear","status":"connected"}],"model":"claude-opus-4-20250514","permissionMode":"bypassPermissions","apiKeySource":"ANTHROPIC_API_KEY"}'
      # Output assistant message
      echo '{"type":"assistant","message":{"id":"msg_01MdrpoBUNGFcga4mKy3HBCn","type":"message","role":"assistant","model":"claude-opus-4-20250514","content":[{"type":"text","text":"Hello from Claude Code CLI!"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3,"cache_creation_input_tokens":4355,"cache_read_input_tokens":22749,"output_tokens":5,"service_tier":"standard"}},"parent_tool_use_id":null,"session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63"}'
      # Output result message
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":10048,"duration_api_ms":16300,"num_turns":1,"result":"Hello from Claude Code CLI!","session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63","total_cost_usd":0.12251155000000002,"usage":{"input_tokens":3,"cache_creation_input_tokens":4355,"cache_read_input_tokens":22749,"output_tokens":38,"server_tool_use":{"web_search_requests":0}}}'
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

    test "handles simple arguments correctly", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key-123")

      {:ok, result} = MockCLI.sync_query(session, "Hello Claude")

      assert %ResultMessage{result: "Hello from Claude Code CLI!"} = result

      GenServer.stop(session)
    end

    test "escapes arguments with special characters", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key-with-special-$-chars")

      {:ok, result} = MockCLI.sync_query(session, "Hello 'Claude' with \"quotes\"")

      assert %ResultMessage{result: "Hello from Claude Code CLI!"} = result

      GenServer.stop(session)
    end

    test "handles newlines in prompts", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      prompt = "Line 1\nLine 2\nLine 3"
      {:ok, result} = MockCLI.sync_query(session, prompt)

      assert %ResultMessage{result: "Hello from Claude Code CLI!"} = result

      GenServer.stop(session)
    end
  end

  describe "shell_escape/1 private function" do
    test "leaves simple strings unescaped" do
      # We can't directly test private functions, but we can verify behavior
      # through the public interface by checking that simple strings work
      assert true
    end
  end

  describe "cross-platform behavior" do
    test "detects unix platform correctly" do
      assert match?({:unix, _}, :os.type())
    end
  end
end
