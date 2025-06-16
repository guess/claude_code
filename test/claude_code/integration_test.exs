defmodule ClaudeCode.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  describe "full query flow with mock CLI" do
    setup do
      # Create a sophisticated mock CLI that simulates real behavior
      mock_dir = Path.join(System.tmp_dir!(), "claude_integration_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Write a mock script that behaves like the real CLI
      File.write!(mock_script, """
      #!/bin/bash

      # Check for required flags
      if [[ "$*" != *"--output-format stream-json"* ]]; then
        echo "Error: Missing required flag --output-format stream-json" >&2
        exit 1
      fi

      # Check for API key
      if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        echo '{"type":"system","subtype":"init","cwd":"/Users/steve/repos/guess/claude_code","session_id":"error-session","tools":[],"mcp_servers":[],"model":"claude-opus-4-20250514","permissionMode":"default","apiKeySource":"ANTHROPIC_API_KEY"}'
        echo '{"type":"result","subtype":"error_during_execution","is_error":true,"duration_ms":100,"duration_api_ms":0,"num_turns":0,"result":"Authentication failed: Missing API key","session_id":"error-session","total_cost_usd":0.0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0}}}'
        exit 1
      fi

      # Simulate different responses based on the prompt
      prompt="${@: -1}"

      case "$prompt" in
        *"error"*)
          echo '{"type":"system","subtype":"init","cwd":"/Users/steve/repos/guess/claude_code","session_id":"error-session","tools":[],"mcp_servers":[],"model":"claude-opus-4-20250514","permissionMode":"default","apiKeySource":"ANTHROPIC_API_KEY"}'
          echo '{"type":"result","subtype":"error_during_execution","is_error":true,"duration_ms":200,"duration_api_ms":0,"num_turns":0,"result":"Simulated error response","session_id":"error-session","total_cost_usd":0.0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0}}}'
          exit 1
          ;;
        *"timeout"*)
          # Simulate timeout by sleeping
          sleep 10
          ;;
        *)
          # Normal response matching real CLI format
          # Output system init message
          echo '{"type":"system","subtype":"init","cwd":"/Users/steve/repos/guess/claude_code","session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63","tools":["Task","Bash","Glob","Grep","LS","exit_plan_mode","Read","Edit","MultiEdit","Write","NotebookRead","NotebookEdit","WebFetch","TodoRead","TodoWrite","WebSearch","mcp__memory__create_entities","mcp__memory__create_relations","mcp__memory__add_observations","mcp__memory__delete_entities","mcp__memory__delete_observations","mcp__memory__delete_relations","mcp__memory__read_graph","mcp__memory__search_nodes","mcp__memory__open_nodes","mcp__filesystem__read_file","mcp__filesystem__read_multiple_files","mcp__filesystem__write_file","mcp__filesystem__edit_file","mcp__filesystem__create_directory","mcp__filesystem__list_directory","mcp__filesystem__directory_tree","mcp__filesystem__move_file","mcp__filesystem__search_files","mcp__filesystem__get_file_info","mcp__filesystem__list_allowed_directories","mcp__github__create_or_update_file","mcp__github__search_repositories","mcp__github__create_repository","mcp__github__get_file_contents","mcp__github__push_files","mcp__github__create_issue","mcp__github__create_pull_request","mcp__github__fork_repository","mcp__github__create_branch","mcp__github__list_commits","mcp__github__list_issues","mcp__github__update_issue","mcp__github__add_issue_comment","mcp__github__search_code","mcp__github__search_issues","mcp__github__search_users","mcp__github__get_issue","mcp__github__get_pull_request","mcp__github__list_pull_requests","mcp__github__create_pull_request_review","mcp__github__merge_pull_request","mcp__github__get_pull_request_files","mcp__github__get_pull_request_status","mcp__github__update_pull_request_branch","mcp__github__get_pull_request_comments","mcp__github__get_pull_request_reviews","mcp__fetch__fetch","mcp__linear__list_comments","mcp__linear__create_comment","mcp__linear__get_document","mcp__linear__list_documents","mcp__linear__get_issue","mcp__linear__get_issue_git_branch_name","mcp__linear__list_issues","mcp__linear__create_issue","mcp__linear__update_issue","mcp__linear__list_issue_statuses","mcp__linear__get_issue_status","mcp__linear__list_my_issues","mcp__linear__list_issue_labels","mcp__linear__list_projects","mcp__linear__get_project","mcp__linear__create_project","mcp__linear__update_project","mcp__linear__list_teams","mcp__linear__get_team","mcp__linear__list_users","mcp__linear__get_user","mcp__linear__search_documentation"],"mcp_servers":[{"name":"memory","status":"connected"},{"name":"filesystem","status":"connected"},{"name":"github","status":"connected"},{"name":"fetch","status":"connected"},{"name":"linear","status":"connected"}],"model":"claude-opus-4-20250514","permissionMode":"bypassPermissions","apiKeySource":"ANTHROPIC_API_KEY"}'
          # Output assistant message
          echo '{"type":"assistant","message":{"id":"msg_01MdrpoBUNGFcga4mKy3HBCn","type":"message","role":"assistant","model":"claude-opus-4-20250514","content":[{"type":"text","text":"Mock response to: '"$prompt"'"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":3,"cache_creation_input_tokens":4355,"cache_read_input_tokens":22749,"output_tokens":5,"service_tier":"standard"}},"parent_tool_use_id":null,"session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63"}'
          # Output result message
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":10048,"duration_api_ms":16300,"num_turns":1,"result":"Mock response to: '"$prompt"'","session_id":"a4c79bab-3a68-425c-988e-0aa6b9151a63","total_cost_usd":0.12251155000000002,"usage":{"input_tokens":3,"cache_creation_input_tokens":4355,"cache_read_input_tokens":22749,"output_tokens":38,"server_tool_use":{"web_search_requests":0}}}'
          exit 0
          ;;
      esac
      """)

      File.chmod!(mock_script, 0o755)

      # Add mock directory to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      :ok
    end

    test "successful query returns response" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      {:ok, response} = ClaudeCode.query(session, "Hello, Claude!")

      assert response == "Mock response to: Hello, Claude!"

      ClaudeCode.stop(session)
    end

    test "error in prompt returns error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      {:error, {:claude_error, message}} = ClaudeCode.query(session, "Please error")

      assert message == "Simulated error response"

      ClaudeCode.stop(session)
    end

    test "missing API key returns authentication error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "")

      {:error, {:claude_error, message}} = ClaudeCode.query(session, "Hello")

      assert message == "Authentication failed: Missing API key"

      ClaudeCode.stop(session)
    end

    test "timeout returns timeout error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      # Use a short timeout
      {:error, :timeout} = ClaudeCode.query(session, "Please timeout", timeout: 1000)

      ClaudeCode.stop(session)
    end

    test "multiple sessions work independently" do
      {:ok, _session1} = ClaudeCode.start_link(api_key: "key1", name: :session1)
      {:ok, _session2} = ClaudeCode.start_link(api_key: "key2", name: :session2)

      {:ok, response1} = ClaudeCode.query(:session1, "From session 1")
      {:ok, response2} = ClaudeCode.query(:session2, "From session 2")

      assert response1 == "Mock response to: From session 1"
      assert response2 == "Mock response to: From session 2"

      ClaudeCode.stop(:session1)
      ClaudeCode.stop(:session2)
    end
  end

  describe "error cases without mock CLI" do
    setup do
      # Ensure no claude binary is in PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "/nonexistent")

      on_exit(fn ->
        System.put_env("PATH", original_path)
      end)

      :ok
    end

    test "CLI not found returns appropriate error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      {:error, {:cli_not_found, message}} = ClaudeCode.query(session, "Hello")

      assert message =~ "Claude CLI not found"
      assert message =~ "Please install Claude Code CLI"

      ClaudeCode.stop(session)
    end
  end
end
