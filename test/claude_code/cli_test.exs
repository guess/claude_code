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

  describe "build_command/4" do
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
          "sonnet",
          []
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

    test "returns error when binary not found" do
      # Clear PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "")

      result = CLI.build_command("test", "key", "model", [])

      assert {:error, {:cli_not_found, message}} = result
      assert message =~ "Claude CLI not found"

      System.put_env("PATH", original_path)
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
