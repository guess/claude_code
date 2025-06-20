defmodule ClaudeCode.CLITest do
  use ExUnit.Case

  alias ClaudeCode.CLI

  describe "find_binary/0" do
    test "finds claude binary when available" do
      # Create a mock claude binary
      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock claude'")
      File.chmod!(mock_binary, 0o755)

      # Add to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      assert {:ok, path} = CLI.find_binary()
      assert path == mock_binary

      # Cleanup
      System.put_env("PATH", original_path)
      File.rm_rf!(mock_dir)
    end

    test "returns error when claude binary not found" do
      # Temporarily clear PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "")

      assert {:error, :not_found} = CLI.find_binary()

      System.put_env("PATH", original_path)
    end
  end

  describe "build_command/3" do
    setup do
      # Create a mock claude binary for testing
      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock claude'")
      File.chmod!(mock_binary, 0o755)

      # Add to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_binary: mock_binary}
    end

    test "builds command with required flags", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          model: "sonnet"
        )

      assert executable == mock_binary
      assert "--output-format" in args
      assert "stream-json" in args
      assert "--verbose" in args
      assert "--print" in args
      assert "--model" in args
      assert "sonnet" in args
      assert "test prompt" in args
    end

    test "builds command with additional options (timeout ignored)", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          model: "opus",
          system_prompt: "You are helpful",
          allowed_tools: ["View", "Bash(git:*)"],
          timeout: 120_000
        )

      assert executable == mock_binary
      assert "--model" in args
      assert "opus" in args
      assert "--system-prompt" in args
      assert "You are helpful" in args
      assert "--allowedTools" in args
      assert "View,Bash(git:*)" in args
      refute "--timeout" in args
      refute "120000" in args
      assert "test prompt" in args
    end

    test "builds command with add_dir option", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          model: "sonnet",
          add_dir: ["/tmp", "/var/log", "/home/user/docs"]
        )

      assert executable == mock_binary
      assert "--add-dir" in args
      assert "/tmp" in args
      assert "--add-dir" in args
      assert "/var/log" in args
      assert "--add-dir" in args
      assert "/home/user/docs" in args
      assert "test prompt" in args
    end

    test "handles empty add_dir list", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          model: "sonnet",
          add_dir: []
        )

      assert executable == mock_binary
      refute "--add-dir" in args
      assert "test prompt" in args
    end

    test "returns error when binary not found" do
      # Clear PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "")

      result = CLI.build_command("test", "key", model: "sonnet")

      assert {:error, {:cli_not_found, message}} = result
      assert message =~ "Claude CLI not found"

      System.put_env("PATH", original_path)
    end
  end

  describe "session continuity support" do
    setup do
      # Create a mock claude binary for testing
      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock claude'")
      File.chmod!(mock_binary, 0o755)

      # Add to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_binary: mock_binary}
    end

    test "builds command with --resume when session_id provided", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          [model: "sonnet"],
          "test-session-123"
        )

      assert executable == mock_binary
      assert "--resume" in args
      assert "test-session-123" in args
      assert "test prompt" in args
    end

    test "builds command without --resume when session_id is nil", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          [model: "sonnet"],
          nil
        )

      assert executable == mock_binary
      refute "--resume" in args
      assert "test prompt" in args
    end

    test "places --resume flag before other options" do
      {:ok, {_executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          [model: "sonnet", system_prompt: "You are helpful"],
          "test-session-123"
        )

      # Find positions of key flags
      resume_pos = Enum.find_index(args, &(&1 == "--resume"))
      model_pos = Enum.find_index(args, &(&1 == "--model"))
      system_pos = Enum.find_index(args, &(&1 == "--system-prompt"))

      # --resume should come before other options
      assert resume_pos < model_pos
      assert resume_pos < system_pos
    end

    test "handles session_id with special characters" do
      session_id = "session-with-dashes_and_underscores-123"

      {:ok, {_executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          [model: "sonnet"],
          session_id
        )

      assert "--resume" in args
      assert session_id in args
    end
  end

  describe "validate_installation/0" do
    test "validates when claude binary exists and works" do
      # Create a mock claude that responds to --version
      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")

      File.write!(mock_binary, """
      #!/bin/bash
      if [[ "$1" == "--version" ]]; then
        echo "1.0.24 (Claude Code)"
        exit 0
      fi
      """)

      File.chmod!(mock_binary, 0o755)

      # Add to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      assert :ok = CLI.validate_installation()

      # Cleanup
      System.put_env("PATH", original_path)
      File.rm_rf!(mock_dir)
    end

    test "returns error for invalid binary" do
      # Create a mock binary that doesn't behave like claude
      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")

      File.write!(mock_binary, """
      #!/bin/bash
      if [[ "$1" == "--version" ]]; then
        echo "something else entirely"
        exit 0
      fi
      """)

      File.chmod!(mock_binary, 0o755)

      # Add to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      assert {:error, {:invalid_binary, _}} = CLI.validate_installation()

      # Cleanup
      System.put_env("PATH", original_path)
      File.rm_rf!(mock_dir)
    end

    test "returns error when binary not found" do
      # Clear PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "")

      assert {:error, {:cli_not_found, _}} = CLI.validate_installation()

      System.put_env("PATH", original_path)
    end
  end
end
