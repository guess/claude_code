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
        echo '{"type": "error", "message": "Authentication failed: Missing API key"}'
        exit 1
      fi

      # Simulate different responses based on the prompt
      prompt="${@: -1}"

      case "$prompt" in
        *"error"*)
          echo '{"type": "error", "message": "Simulated error response"}'
          exit 1
          ;;
        *"timeout"*)
          # Simulate timeout by sleeping
          sleep 10
          ;;
        *)
          # Normal response matching real CLI format
          echo '{"type":"system","subtype":"init","session_id":"test-123"}'
          echo '{"type":"assistant","message":{"content":[{"text":"Mock response to: '"$prompt"'","type":"text"}]}}'
          echo '{"type":"result","subtype":"success","result":"Mock response to: '"$prompt"'","session_id":"test-123"}'
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

      {:ok, response} = ClaudeCode.query_sync(session, "Hello, Claude!")

      assert response == "Mock response to: Hello, Claude!"

      ClaudeCode.stop(session)
    end

    test "error in prompt returns error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      {:error, {:claude_error, message}} = ClaudeCode.query_sync(session, "Please error")

      assert message == "Simulated error response"

      ClaudeCode.stop(session)
    end

    test "missing API key returns authentication error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "")

      {:error, {:claude_error, message}} = ClaudeCode.query_sync(session, "Hello")

      assert message == "Authentication failed: Missing API key"

      ClaudeCode.stop(session)
    end

    test "timeout returns timeout error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      # Use a short timeout
      {:error, :timeout} = ClaudeCode.query_sync(session, "Please timeout", timeout: 1000)

      ClaudeCode.stop(session)
    end

    test "multiple sessions work independently" do
      {:ok, _session1} = ClaudeCode.start_link(api_key: "key1", name: :session1)
      {:ok, _session2} = ClaudeCode.start_link(api_key: "key2", name: :session2)

      {:ok, response1} = ClaudeCode.query_sync(:session1, "From session 1")
      {:ok, response2} = ClaudeCode.query_sync(:session2, "From session 2")

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

      {:error, {:cli_not_found, message}} = ClaudeCode.query_sync(session, "Hello")

      assert message =~ "Claude CLI not found"
      assert message =~ "Please install Claude Code CLI"

      ClaudeCode.stop(session)
    end
  end
end
