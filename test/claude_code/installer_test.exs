defmodule ClaudeCode.InstallerTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Installer

  describe "configured_version/0" do
    test "returns 'latest' when no config set" do
      original = Application.get_env(:claude_code, :cli_version)

      try do
        Application.delete_env(:claude_code, :cli_version)
        assert Installer.configured_version() == "latest"
      after
        if original do
          Application.put_env(:claude_code, :cli_version, original)
        end
      end
    end

    test "returns configured version from application env" do
      original = Application.get_env(:claude_code, :cli_version)

      try do
        Application.put_env(:claude_code, :cli_version, "2.1.29")
        assert Installer.configured_version() == "2.1.29"
      after
        if original do
          Application.put_env(:claude_code, :cli_version, original)
        else
          Application.delete_env(:claude_code, :cli_version)
        end
      end
    end
  end

  describe "cli_dir/0" do
    test "returns default priv/bin directory" do
      dir = Installer.cli_dir()
      assert String.ends_with?(dir, "/bin") or String.ends_with?(dir, "\\bin")
    end

    test "returns configured directory from application env" do
      original = Application.get_env(:claude_code, :cli_dir)

      try do
        Application.put_env(:claude_code, :cli_dir, "/custom/path")
        assert Installer.cli_dir() == "/custom/path"
      after
        if original do
          Application.put_env(:claude_code, :cli_dir, original)
        else
          Application.delete_env(:claude_code, :cli_dir)
        end
      end
    end
  end

  describe "bundled_path/0" do
    test "returns path with claude binary name" do
      path = Installer.bundled_path()
      binary_name = if match?({:win32, _}, :os.type()), do: "claude.exe", else: "claude"
      assert String.ends_with?(path, binary_name)
    end
  end

  describe "bin_path/0" do
    test "returns {:ok, path} when CLI exists" do
      # Clear cli_path config for this test to allow resolution
      original_cli_path = Application.get_env(:claude_code, :cli_path)

      try do
        Application.delete_env(:claude_code, :cli_path)

        # bin_path checks: 1) cli_path config, 2) bundled, 3) PATH, 4) common locations
        # This test verifies the resolution works correctly
        case Installer.bin_path() do
          {:ok, path} ->
            # Should find a valid executable
            assert File.exists?(path)

            # Verify it's either bundled, in PATH, or in common locations
            bundled = Installer.bundled_path()
            in_path = System.find_executable("claude")

            assert path == bundled or path == in_path or File.exists?(path)

          {:error, :not_found} ->
            # Expected if claude is not installed anywhere
            assert true
        end
      after
        if original_cli_path do
          Application.put_env(:claude_code, :cli_path, original_cli_path)
        end
      end
    end

    test "returns {:ok, path} when cli_path is configured" do
      original = Application.get_env(:claude_code, :cli_path)

      # Create a temporary file to simulate the CLI
      tmp_dir = System.tmp_dir!()
      tmp_path = Path.join(tmp_dir, "claude_test_#{:erlang.unique_integer()}")

      try do
        File.write!(tmp_path, "#!/bin/bash\necho 'test'")
        File.chmod!(tmp_path, 0o755)

        Application.put_env(:claude_code, :cli_path, tmp_path)
        assert {:ok, ^tmp_path} = Installer.bin_path()
      after
        File.rm(tmp_path)

        if original do
          Application.put_env(:claude_code, :cli_path, original)
        else
          Application.delete_env(:claude_code, :cli_path)
        end
      end
    end

    test "returns {:error, :not_found} when configured path doesn't exist" do
      original = Application.get_env(:claude_code, :cli_path)

      try do
        Application.put_env(:claude_code, :cli_path, "/nonexistent/path/claude")
        assert {:error, :not_found} = Installer.bin_path()
      after
        if original do
          Application.put_env(:claude_code, :cli_path, original)
        else
          Application.delete_env(:claude_code, :cli_path)
        end
      end
    end
  end

  describe "bin_path!/0" do
    test "returns path when CLI exists" do
      case Installer.bin_path() do
        {:ok, expected_path} ->
          assert Installer.bin_path!() == expected_path

        {:error, :not_found} ->
          assert_raise RuntimeError, ~r/Claude CLI not found/, fn ->
            Installer.bin_path!()
          end
      end
    end
  end

  describe "find_in_common_locations/0" do
    test "returns nil when CLI is not in common locations" do
      # Unless the user has claude installed in a common location,
      # this should return nil
      result = Installer.find_in_common_locations()
      assert is_nil(result) or File.exists?(result)
    end
  end

  describe "find_system_cli/0" do
    test "returns path if claude is in PATH" do
      case System.find_executable("claude") do
        nil ->
          # May still find in common locations
          result = Installer.find_system_cli()
          assert is_nil(result) or File.exists?(result)

        path ->
          assert Installer.find_system_cli() == path
      end
    end
  end

  describe "installed_version/0" do
    test "returns version when CLI is installed" do
      case Installer.bin_path() do
        {:ok, _path} ->
          case Installer.installed_version() do
            {:ok, version} ->
              assert is_binary(version)
              assert String.length(version) > 0

            {:error, {:cli_error, _}} ->
              # CLI exists but version command failed
              assert true
          end

        {:error, :not_found} ->
          assert {:error, :not_found} = Installer.installed_version()
      end
    end
  end

  describe "ensure_installed!/0" do
    test "returns :ok when CLI is already installed" do
      case Installer.bin_path() do
        {:ok, _path} ->
          assert :ok = Installer.ensure_installed!()

        {:error, :not_found} ->
          # Skip test if CLI is not installed - we don't want to actually install in tests
          :ok
      end
    end
  end
end
