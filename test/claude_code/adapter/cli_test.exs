defmodule ClaudeCode.Adapter.CLITest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.CLI

  # ============================================================================
  # shell_escape/1 Tests
  # ============================================================================

  describe "shell_escape/1" do
    test "returns simple strings unchanged" do
      assert CLI.shell_escape("hello") == "hello"
      assert CLI.shell_escape("foo123") == "foo123"
      assert CLI.shell_escape("path/to/file") == "path/to/file"
    end

    test "escapes empty strings" do
      assert CLI.shell_escape("") == "''"
    end

    test "escapes strings with spaces" do
      assert CLI.shell_escape("hello world") == "'hello world'"
      assert CLI.shell_escape("path with spaces") == "'path with spaces'"
    end

    test "escapes strings with single quotes" do
      assert CLI.shell_escape("it's") == "'it'\\''s'"
      assert CLI.shell_escape("don't") == "'don'\\''t'"
    end

    test "escapes strings with double quotes" do
      assert CLI.shell_escape("say \"hello\"") == "'say \"hello\"'"
    end

    test "escapes strings with dollar signs" do
      assert CLI.shell_escape("$HOME") == "'$HOME'"
      assert CLI.shell_escape("cost: $100") == "'cost: $100'"
    end

    test "escapes strings with backticks" do
      assert CLI.shell_escape("`command`") == "'`command`'"
    end

    test "escapes strings with backslashes" do
      assert CLI.shell_escape("path\\to\\file") == "'path\\to\\file'"
    end

    test "escapes strings with newlines" do
      assert CLI.shell_escape("line1\nline2") == "'line1\nline2'"
    end

    test "escapes strings with multiple special characters" do
      assert CLI.shell_escape("it's $100") == "'it'\\''s $100'"
      assert CLI.shell_escape("say \"hi\" to '$USER'") == "'say \"hi\" to '\\''$USER'\\'''"
    end

    test "escapes strings with semicolons (command separator)" do
      # Critical for env vars like LS_COLORS which contain semicolons
      assert CLI.shell_escape("rs=0:di=01;34") == "'rs=0:di=01;34'"
      assert CLI.shell_escape("cmd1;cmd2") == "'cmd1;cmd2'"
    end

    test "escapes strings with ampersands (background/and operator)" do
      assert CLI.shell_escape("cmd1&cmd2") == "'cmd1&cmd2'"
      assert CLI.shell_escape("cmd1 && cmd2") == "'cmd1 && cmd2'"
    end

    test "escapes strings with pipes (command chaining)" do
      assert CLI.shell_escape("cmd1|cmd2") == "'cmd1|cmd2'"
      assert CLI.shell_escape("cmd1 | cmd2") == "'cmd1 | cmd2'"
    end

    test "escapes strings with parentheses (subshell)" do
      assert CLI.shell_escape("(cmd)") == "'(cmd)'"
      assert CLI.shell_escape("$(cmd)") == "'$(cmd)'"
    end

    test "converts non-strings to strings" do
      assert CLI.shell_escape(123) == "123"
      assert CLI.shell_escape(:atom) == "atom"
    end
  end

  # ============================================================================
  # extract_lines/1 Tests
  # ============================================================================

  describe "extract_lines/1" do
    test "extracts complete lines from buffer" do
      {lines, remaining} = CLI.extract_lines("line1\nline2\nline3\n")
      assert lines == ["line1", "line2", "line3"]
      assert remaining == ""
    end

    test "keeps incomplete line in remaining buffer" do
      {lines, remaining} = CLI.extract_lines("line1\nline2\nincomplete")
      assert lines == ["line1", "line2"]
      assert remaining == "incomplete"
    end

    test "handles empty buffer" do
      {lines, remaining} = CLI.extract_lines("")
      assert lines == []
      assert remaining == ""
    end

    test "handles buffer with no complete lines" do
      {lines, remaining} = CLI.extract_lines("partial")
      assert lines == []
      assert remaining == "partial"
    end

    test "handles buffer with single complete line" do
      {lines, remaining} = CLI.extract_lines("single\n")
      assert lines == ["single"]
      assert remaining == ""
    end

    test "handles buffer with only newline" do
      {lines, remaining} = CLI.extract_lines("\n")
      assert lines == [""]
      assert remaining == ""
    end

    test "handles buffer with multiple consecutive newlines" do
      {lines, remaining} = CLI.extract_lines("line1\n\nline3\n")
      assert lines == ["line1", "", "line3"]
      assert remaining == ""
    end

    test "handles JSON lines (typical CLI output)" do
      json1 = ~s({"type":"system","subtype":"init"})
      json2 = ~s({"type":"assistant","message":{}})
      buffer = "#{json1}\n#{json2}\n"

      {lines, remaining} = CLI.extract_lines(buffer)
      assert lines == [json1, json2]
      assert remaining == ""
    end

    test "handles partial JSON accumulation" do
      # First chunk
      {lines1, remaining1} = CLI.extract_lines(~s({"type":"sys))
      assert lines1 == []
      assert remaining1 == ~s({"type":"sys)

      # Second chunk arrives
      {lines2, remaining2} = CLI.extract_lines(remaining1 <> ~s(tem"}\n{"type":))
      assert lines2 == [~s({"type":"system"})]
      assert remaining2 == ~s({"type":)

      # Final chunk
      {lines3, remaining3} = CLI.extract_lines(remaining2 <> ~s("result"}\n))
      assert lines3 == [~s({"type":"result"})]
      assert remaining3 == ""
    end
  end

  # ============================================================================
  # Adapter Behaviour Tests
  # ============================================================================

  describe "adapter behaviour" do
    test "implements ClaudeCode.Adapter behaviour" do
      behaviours = CLI.__info__(:attributes)[:behaviour] || []
      assert ClaudeCode.Adapter in behaviours
    end
  end

  describe "new behaviour callbacks" do
    test "implements all ClaudeCode.Adapter callbacks" do
      callbacks = ClaudeCode.Adapter.behaviour_info(:callbacks)

      Enum.each(callbacks, fn {fun, arity} ->
        assert function_exported?(ClaudeCode.Adapter.CLI, fun, arity),
               "Missing callback: #{fun}/#{arity}"
      end)
    end
  end

  # ============================================================================
  # Adapter Status Lifecycle Tests
  # ============================================================================

  describe "adapter status lifecycle" do
    test "starts in provisioning status and transitions to ready" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        CLI.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      state = :sys.get_state(adapter)
      assert state.status == :ready
      assert state.port != nil

      GenServer.stop(adapter)
    end

    test "transitions to disconnected on provisioning failure" do
      session = self()

      {:ok, adapter} =
        CLI.start_link(session,
          api_key: "test-key",
          cli_path: "/nonexistent/path/to/claude"
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, {:error, _reason}}, 5000

      state = :sys.get_state(adapter)
      assert state.status == :disconnected
      assert state.port == nil

      GenServer.stop(adapter)
    end

    test "ensure_connected returns error during provisioning" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        CLI.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # Simulate provisioning state by replacing the adapter's state
      # This tests the ensure_connected guard clause directly
      :sys.replace_state(adapter, fn state ->
        %{state | status: :provisioning, port: nil}
      end)

      result = CLI.send_query(adapter, make_ref(), "test", [])

      assert {:error, :provisioning} = result

      GenServer.stop(adapter)
    end
  end

  # ============================================================================
  # Environment Variable Tests
  # ============================================================================

  describe "sdk_env_vars/0" do
    test "returns SDK-required environment variables" do
      env = CLI.sdk_env_vars()

      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
    end

    test "version matches application version" do
      env = CLI.sdk_env_vars()
      expected_version = :claude_code |> Application.spec(:vsn) |> to_string()

      assert env["CLAUDE_AGENT_SDK_VERSION"] == expected_version
    end
  end

  describe "build_env/2" do
    test "includes system environment variables" do
      # Set a known system env var for the test
      System.put_env("CLAUDE_CODE_TEST_VAR", "test_value")

      try do
        env = CLI.build_env([], nil)

        assert env["CLAUDE_CODE_TEST_VAR"] == "test_value"
      after
        System.delete_env("CLAUDE_CODE_TEST_VAR")
      end
    end

    test "user env overrides system env" do
      System.put_env("CLAUDE_CODE_TEST_VAR", "system_value")

      try do
        env = CLI.build_env([env: %{"CLAUDE_CODE_TEST_VAR" => "user_value"}], nil)

        assert env["CLAUDE_CODE_TEST_VAR"] == "user_value"
      after
        System.delete_env("CLAUDE_CODE_TEST_VAR")
      end
    end

    test "SDK vars are always present" do
      env = CLI.build_env([], nil)

      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
    end

    test "SDK vars override user env" do
      # User cannot override SDK-required vars
      env =
        CLI.build_env(
          [
            env: %{
              "CLAUDE_CODE_ENTRYPOINT" => "malicious",
              "CLAUDE_AGENT_SDK_VERSION" => "0.0.0"
            }
          ],
          nil
        )

      # SDK vars win
      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
    end

    test "api_key overrides ANTHROPIC_API_KEY from system" do
      System.put_env("ANTHROPIC_API_KEY", "system_key")

      try do
        env = CLI.build_env([], "option_api_key")

        assert env["ANTHROPIC_API_KEY"] == "option_api_key"
      after
        System.delete_env("ANTHROPIC_API_KEY")
      end
    end

    test "api_key overrides ANTHROPIC_API_KEY from user env" do
      env =
        CLI.build_env(
          [env: %{"ANTHROPIC_API_KEY" => "user_env_key"}],
          "option_api_key"
        )

      assert env["ANTHROPIC_API_KEY"] == "option_api_key"
    end

    test "user env ANTHROPIC_API_KEY used when no api_key option" do
      env = CLI.build_env([env: %{"ANTHROPIC_API_KEY" => "user_env_key"}], nil)

      assert env["ANTHROPIC_API_KEY"] == "user_env_key"
    end

    test "default empty env option" do
      # When :env not specified, defaults to empty map
      env = CLI.build_env([], nil)

      # Should still have SDK vars
      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
    end

    test "custom environment variables are passed through" do
      env =
        CLI.build_env(
          [
            env: %{
              "MY_CUSTOM_VAR" => "custom_value",
              "ANOTHER_VAR" => "another_value"
            }
          ],
          nil
        )

      assert env["MY_CUSTOM_VAR"] == "custom_value"
      assert env["ANOTHER_VAR"] == "another_value"
    end

    test "preserves PATH from system" do
      path = System.get_env("PATH")

      env = CLI.build_env([], nil)

      assert env["PATH"] == path
    end

    test "allows extending PATH" do
      original_path = System.get_env("PATH")
      extended_path = "/custom/bin:#{original_path}"

      env = CLI.build_env([env: %{"PATH" => extended_path}], nil)

      assert env["PATH"] == extended_path
    end

    test "sets file checkpointing env var when enabled" do
      env = CLI.build_env([enable_file_checkpointing: true], nil)

      assert env["CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"] == "true"
    end

    test "does not set file checkpointing env var when disabled" do
      env = CLI.build_env([enable_file_checkpointing: false], nil)

      refute Map.has_key?(env, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")
    end

    test "does not set file checkpointing env var by default" do
      env = CLI.build_env([], nil)

      refute Map.has_key?(env, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")
    end
  end
end
