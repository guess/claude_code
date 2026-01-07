defmodule ClaudeCode.IntegrationTest do
  use ExUnit.Case

  alias ClaudeCode.Message.ResultMessage

  @moduletag :integration

  describe "full query flow with mock CLI" do
    setup do
      # Create a sophisticated mock CLI that simulates real behavior
      mock_dir = Path.join(System.tmp_dir!(), "claude_integration_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Write a streaming-aware mock script that behaves like the real CLI
      File.write!(mock_script, """
      #!/bin/bash

      # Check for required flags
      if [[ "$*" != *"--input-format stream-json"* ]]; then
        echo "Error: Missing required flag --input-format stream-json" >&2
        exit 1
      fi

      # Check for API key and output system init
      if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"error-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"default","apiKeySource":"ANTHROPIC_API_KEY"}'
      else
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"int-test-session","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
      fi

      # Read from stdin (streaming mode) and respond to each message
      while IFS= read -r line; do
        # Extract the prompt from the JSON message
        prompt=$(echo "$line" | grep -o '"content":"[^"]*"' | sed 's/"content":"\\([^"]*\\)"/\\1/')

        # Check for API key error case
        if [[ -z "$ANTHROPIC_API_KEY" ]]; then
          echo '{"type":"result","subtype":"error_during_execution","is_error":true,"duration_ms":100,"duration_api_ms":0,"num_turns":0,"result":"Authentication failed: Missing API key","session_id":"error-session","total_cost_usd":0.0,"usage":{}}'
          continue
        fi

        case "$prompt" in
          *error*)
            echo '{"type":"result","subtype":"error_during_execution","is_error":true,"duration_ms":200,"duration_api_ms":0,"num_turns":0,"result":"Simulated error response","session_id":"int-test-session","total_cost_usd":0.0,"usage":{}}'
            ;;
          *auth_fail*)
            echo '{"type":"result","subtype":"error_during_execution","is_error":true,"duration_ms":100,"duration_api_ms":0,"num_turns":0,"result":"Authentication failed: Missing API key","session_id":"int-test-session","total_cost_usd":0.0,"usage":{}}'
            ;;
          *timeout*)
            # Simulate timeout by sleeping
            sleep 10
            ;;
          *)
            # Normal response
            echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Mock response to: '"$prompt"'"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"int-test-session"}'
            sleep 0.02
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":80,"num_turns":1,"result":"Mock response to: '"$prompt"'","session_id":"int-test-session","total_cost_usd":0.001,"usage":{}}'
            ;;
        esac
      done

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

      :ok
    end

    test "successful query returns response" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      {:ok, result} = MockCLI.sync_query(session, "Hello, Claude!")

      assert %ResultMessage{result: "Mock response to: Hello, Claude!"} = result

      ClaudeCode.stop(session)
    end

    test "error in prompt returns error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      {:error, result} = MockCLI.sync_query(session, "Please error")

      assert %ResultMessage{is_error: true, result: "Simulated error response"} = result

      ClaudeCode.stop(session)
    end

    test "authentication error is handled correctly" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      # Use prompt trigger for auth failure simulation
      {:error, result} = MockCLI.sync_query(session, "test auth_fail")

      assert %ResultMessage{is_error: true, result: "Authentication failed: Missing API key"} = result

      ClaudeCode.stop(session)
    end

    test "timeout returns timeout error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-api-key")

      # Use a short timeout - the stream will throw when it times out
      thrown =
        session
        |> ClaudeCode.stream("Please timeout", timeout: 1000)
        |> Enum.to_list()
        |> catch_throw()

      assert {:stream_timeout, _ref} = thrown

      ClaudeCode.stop(session)
    end

    test "multiple sessions work independently" do
      {:ok, _session1} = ClaudeCode.start_link(api_key: "key1", name: :session1)
      {:ok, _session2} = ClaudeCode.start_link(api_key: "key2", name: :session2)

      {:ok, result1} = MockCLI.sync_query(:session1, "From session 1")
      {:ok, result2} = MockCLI.sync_query(:session2, "From session 2")

      assert %ResultMessage{result: "Mock response to: From session 1"} = result1
      assert %ResultMessage{result: "Mock response to: From session 2"} = result2

      ClaudeCode.stop(:session1)
      ClaudeCode.stop(:session2)
    end
  end

  describe "error cases without mock CLI" do
    setup do
      # Set PATH to only system directories (not where claude would be)
      original_path = System.get_env("PATH")
      System.put_env("PATH", "/bin:/usr/bin")

      on_exit(fn ->
        System.put_env("PATH", original_path)
      end)

      :ok
    end

    test "CLI not found returns appropriate error" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      # Stream should throw init error when CLI not found
      error =
        session
        |> ClaudeCode.stream("Hello")
        |> Enum.to_list()
        |> catch_throw()

      assert {:stream_init_error, {:cli_not_found, _message}} = error

      ClaudeCode.stop(session)
    end
  end
end
