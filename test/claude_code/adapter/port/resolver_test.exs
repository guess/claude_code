defmodule ClaudeCode.Adapter.Port.ResolverTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Port.Resolver

  describe "find_binary/1 with explicit path" do
    test "finds claude binary via explicit string path" do
      mock_dir = Path.join(System.tmp_dir!(), "claude_resolver_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock claude'")
      File.chmod!(mock_binary, 0o755)

      assert {:ok, path} = Resolver.find_binary(cli_path: mock_binary)
      assert path == mock_binary

      File.rm_rf!(mock_dir)
    end

    test "returns error when explicit path doesn't exist" do
      assert {:error, :not_found} = Resolver.find_binary(cli_path: "/nonexistent/path/claude")
    end
  end

  describe "find_binary/1 with :global mode" do
    test "returns :not_found when claude is not installed globally" do
      original_path = Application.get_env(:claude_code, :cli_path)
      original_system = Application.get_env(:claude_code, ClaudeCode.System)

      try do
        Application.delete_env(:claude_code, :cli_path)
        # Ensure we use the real System.find_executable, not a mock
        Application.delete_env(:claude_code, ClaudeCode.System)

        case Resolver.find_binary(cli_path: :global) do
          {:ok, path} ->
            # If claude is actually installed, verify the path exists
            assert File.exists?(path)

          {:error, :not_found} ->
            # Expected when claude is not installed
            assert true
        end
      after
        if original_path, do: Application.put_env(:claude_code, :cli_path, original_path)
        if original_system, do: Application.put_env(:claude_code, ClaudeCode.System, original_system)
      end
    end
  end

  describe "find_binary/1 respects app config" do
    test "uses app config cli_path when no option provided" do
      original = Application.get_env(:claude_code, :cli_path)

      mock_dir = Path.join(System.tmp_dir!(), "claude_resolver_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)
      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock'")
      File.chmod!(mock_binary, 0o755)

      try do
        Application.put_env(:claude_code, :cli_path, mock_binary)
        assert {:ok, ^mock_binary} = Resolver.find_binary([])
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

      mock_dir = Path.join(System.tmp_dir!(), "claude_resolver_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)
      mock_binary = Path.join(mock_dir, "claude")
      File.write!(mock_binary, "#!/bin/bash\necho 'mock'")
      File.chmod!(mock_binary, 0o755)

      try do
        Application.put_env(:claude_code, :cli_path, :global)
        assert {:ok, ^mock_binary} = Resolver.find_binary(cli_path: mock_binary)
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

  describe "validate_installation/1" do
    test "validates when claude binary exists and works" do
      mock_dir = Path.join(System.tmp_dir!(), "claude_resolver_test_#{:rand.uniform(100_000)}")
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

      assert :ok = Resolver.validate_installation(cli_path: mock_binary)

      File.rm_rf!(mock_dir)
    end

    test "returns error for invalid binary" do
      mock_dir = Path.join(System.tmp_dir!(), "claude_resolver_test_#{:rand.uniform(100_000)}")
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

      assert {:error, {:invalid_binary, _}} = Resolver.validate_installation(cli_path: mock_binary)

      File.rm_rf!(mock_dir)
    end

    test "returns error when binary not found" do
      assert {:error, {:cli_not_found, _}} =
               Resolver.validate_installation(cli_path: "/nonexistent/path/claude")
    end
  end
end
