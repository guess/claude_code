defmodule ClaudeCode.CLITest do
  use ExUnit.Case, async: true

  alias ClaudeCode.CLI

  describe "find_binary/1 with explicit path" do
    test "finds claude binary via explicit string path" do
      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock claude'")
      File.chmod!(mock_binary, 0o755)

      assert {:ok, path} = CLI.find_binary(cli_path: mock_binary)
      assert path == mock_binary

      File.rm_rf!(mock_dir)
    end

    test "returns error when explicit path doesn't exist" do
      assert {:error, :not_found} = CLI.find_binary(cli_path: "/nonexistent/path/claude")
    end
  end

  describe "find_binary/1 with :global mode" do
    test "returns :not_found when claude is not installed globally" do
      # Temporarily clear any app config
      original = Application.get_env(:claude_code, :cli_path)

      try do
        Application.delete_env(:claude_code, :cli_path)

        case CLI.find_binary(cli_path: :global) do
          {:ok, path} ->
            # If claude is actually installed, verify the path exists
            assert File.exists?(path)

          {:error, :not_found} ->
            # Expected when claude is not installed
            assert true
        end
      after
        if original, do: Application.put_env(:claude_code, :cli_path, original)
      end
    end
  end

  describe "find_binary/1 with :bundled mode" do
    test "defaults to :bundled when no cli_path specified" do
      # Clear any app config
      original = Application.get_env(:claude_code, :cli_path)

      try do
        Application.delete_env(:claude_code, :cli_path)

        # With no cli_path option and no app config, defaults to :bundled
        # This may auto-install or return error depending on environment
        result = CLI.find_binary([])

        case result do
          {:ok, path} ->
            # Should be the bundled path
            assert String.ends_with?(path, "claude")

          {:error, _reason} ->
            # Expected if auto-install fails (e.g., no network in test)
            assert true
        end
      after
        if original, do: Application.put_env(:claude_code, :cli_path, original)
      end
    end
  end

  describe "find_binary/1 respects app config" do
    test "uses app config cli_path when no option provided" do
      original = Application.get_env(:claude_code, :cli_path)

      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)
      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock'")
      File.chmod!(mock_binary, 0o755)

      try do
        Application.put_env(:claude_code, :cli_path, mock_binary)
        assert {:ok, ^mock_binary} = CLI.find_binary([])
      after
        if original do
          Application.put_env(:claude_code, :cli_path, original)
        else
          Application.delete_env(:claude_code, :cli_path)
        end

        File.rm_rf!(mock_dir)
      end
    end

    test "option cli_path overrides app config" do
      original = Application.get_env(:claude_code, :cli_path)

      mock_dir = Path.join(System.tmp_dir!(), "claude_cli_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)
      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock'")
      File.chmod!(mock_binary, 0o755)

      try do
        # App config says :global, but option says explicit path
        Application.put_env(:claude_code, :cli_path, :global)
        assert {:ok, ^mock_binary} = CLI.find_binary(cli_path: mock_binary)
      after
        if original do
          Application.put_env(:claude_code, :cli_path, original)
        else
          Application.delete_env(:claude_code, :cli_path)
        end

        File.rm_rf!(mock_dir)
      end
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

      on_exit(fn ->
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_binary: mock_binary}
    end

    test "builds command with required flags", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          model: "sonnet",
          cli_path: mock_binary
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
          timeout: 120_000,
          cli_path: mock_binary
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
          add_dir: ["/tmp", "/var/log", "/home/user/docs"],
          cli_path: mock_binary
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
          add_dir: [],
          cli_path: mock_binary
        )

      assert executable == mock_binary
      refute "--add-dir" in args
      assert "test prompt" in args
    end

    test "returns error when binary not found" do
      result =
        CLI.build_command(
          "test",
          "key",
          model: "sonnet",
          cli_path: "/nonexistent/path/claude"
        )

      assert {:error, {:cli_not_found, message}} = result
      assert message =~ "Claude CLI not found"
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

      on_exit(fn ->
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_binary: mock_binary}
    end

    test "builds command with --resume when session_id provided", %{mock_binary: mock_binary} do
      {:ok, {executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          [model: "sonnet", cli_path: mock_binary],
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
          [model: "sonnet", cli_path: mock_binary],
          nil
        )

      assert executable == mock_binary
      refute "--resume" in args
      assert "test prompt" in args
    end

    test "places --resume flag before other options", %{mock_binary: mock_binary} do
      {:ok, {_executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          [model: "sonnet", system_prompt: "You are helpful", cli_path: mock_binary],
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

    test "handles session_id with special characters", %{mock_binary: mock_binary} do
      session_id = "session-with-dashes_and_underscores-123"

      {:ok, {_executable, args}} =
        CLI.build_command(
          "test prompt",
          "test-api-key",
          [model: "sonnet", cli_path: mock_binary],
          session_id
        )

      assert "--resume" in args
      assert session_id in args
    end
  end

  describe "validate_installation/1" do
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

      assert :ok = CLI.validate_installation(cli_path: mock_binary)

      # Cleanup
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

      assert {:error, {:invalid_binary, _}} = CLI.validate_installation(cli_path: mock_binary)

      # Cleanup
      File.rm_rf!(mock_dir)
    end

    test "returns error when binary not found" do
      assert {:error, {:cli_not_found, _}} =
               CLI.validate_installation(cli_path: "/nonexistent/path/claude")
    end
  end
end
