defmodule ClaudeCode.Adapter.Port.InstallerTest do
  use ExUnit.Case, async: true

  import Mox

  alias ClaudeCode.Adapter.Port.Installer
  alias ClaudeCode.SystemCmd.Mock

  setup :verify_on_exit!

  describe "configured_version/0" do
    test "returns default version when no config set" do
      original = Application.get_env(:claude_code, :cli_version)

      try do
        Application.delete_env(:claude_code, :cli_version)
        # Default is the SDK's tested CLI version, not "latest"
        version = Installer.configured_version()
        assert is_binary(version)
        assert version =~ ~r/^\d+\.\d+\.\d+$/
      after
        if original do
          Application.put_env(:claude_code, :cli_version, original)
        end
      end
    end

    test "returns configured version from application env" do
      original = Application.get_env(:claude_code, :cli_version)

      try do
        Application.put_env(:claude_code, :cli_version, "2.0.0")
        assert Installer.configured_version() == "2.0.0"
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

  describe "find_in_common_locations/0" do
    test "returns nil when CLI is not in common locations" do
      # Unless the user has claude installed in a common location,
      # this should return nil
      result = Installer.find_in_common_locations()
      assert is_nil(result) or File.exists?(result)
    end
  end

  describe "version_of/1" do
    test "returns version from a binary that outputs version info" do
      mock_dir = Path.join(System.tmp_dir!(), "claude_version_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")

      File.write!(mock_binary, """
      #!/bin/bash
      echo "2.1.37 (Claude Code)"
      """)

      File.chmod!(mock_binary, 0o755)

      # Stub mock to delegate to real System.cmd for version_of tests
      stub(Mock, :cmd, fn command, args, opts ->
        System.cmd(command, args, opts)
      end)

      Application.put_env(:claude_code, :system_cmd_module, Mock)

      try do
        assert {:ok, "2.1.37"} = Installer.version_of(mock_binary)
      after
        Application.delete_env(:claude_code, :system_cmd_module)
        File.rm_rf!(mock_dir)
      end
    end

    test "returns error when binary doesn't exist" do
      stub(Mock, :cmd, fn command, args, opts ->
        System.cmd(command, args, opts)
      end)

      Application.put_env(:claude_code, :system_cmd_module, Mock)

      try do
        assert {:error, {:execution_failed, _}} = Installer.version_of("/nonexistent/binary")
      after
        Application.delete_env(:claude_code, :system_cmd_module)
      end
    end

    test "returns error when binary fails" do
      mock_dir = Path.join(System.tmp_dir!(), "claude_version_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_binary = Path.join(mock_dir, "claude")

      File.write!(mock_binary, """
      #!/bin/bash
      echo "error" >&2
      exit 1
      """)

      File.chmod!(mock_binary, 0o755)

      stub(Mock, :cmd, fn command, args, opts ->
        System.cmd(command, args, opts)
      end)

      Application.put_env(:claude_code, :system_cmd_module, Mock)

      try do
        assert {:error, {:cli_error, _}} = Installer.version_of(mock_binary)
      after
        Application.delete_env(:claude_code, :system_cmd_module)
        File.rm_rf!(mock_dir)
      end
    end
  end

  describe "cli_not_found_message/0" do
    test "returns a helpful error message" do
      message = Installer.cli_not_found_message()

      assert message =~ "Claude CLI not found"
      assert message =~ "mix claude_code.install"
      assert message =~ "curl -fsSL"
      assert message =~ "cli_path"
    end
  end

  describe "install!/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_install_test_#{:erlang.unique_integer([:positive])}")

      original_cli_dir = Application.get_env(:claude_code, :cli_dir)
      Application.put_env(:claude_code, :cli_dir, tmp_dir)
      Application.put_env(:claude_code, :system_cmd_module, Mock)

      on_exit(fn ->
        if original_cli_dir do
          Application.put_env(:claude_code, :cli_dir, original_cli_dir)
        else
          Application.delete_env(:claude_code, :cli_dir)
        end

        Application.delete_env(:claude_code, :system_cmd_module)
        File.rm_rf(tmp_dir)
      end)

      %{tmp_dir: tmp_dir}
    end

    test "creates cli_dir and installs binary on success", %{tmp_dir: tmp_dir} do
      refute File.exists?(tmp_dir)

      # The install script runs in a temp dir with HOME set.
      # On success, it should find the binary at <tmp>/.local/bin/claude
      # and copy it to the bundled path.
      expect(Mock, :cmd, fn "bash", ["-c", script_cmd], opts ->
        assert script_cmd =~ "curl -fsSL"
        assert script_cmd =~ "claude.ai/install.sh"

        # Simulate what the install script does: place a binary at <HOME>/.local/bin/claude
        env = Keyword.get(opts, :env, [])
        home = Enum.find_value(env, fn {"HOME", v} -> v end)
        assert home, "HOME should be set in env"

        bin_dir = Path.join([home, ".local", "bin"])
        File.mkdir_p!(bin_dir)
        binary_path = Path.join(bin_dir, "claude")

        File.write!(binary_path, """
        #!/bin/bash
        echo "2.1.37 (Claude Code)"
        """)

        File.chmod!(binary_path, 0o755)

        {"Installation complete", 0}
      end)

      # version_from_binary will call version_of on the copied binary
      expect(Mock, :cmd, fn path, ["--version"], _opts ->
        assert String.ends_with?(path, "/claude")
        {"2.1.37 (Claude Code)", 0}
      end)

      assert :ok = Installer.install!()
      assert File.exists?(tmp_dir)
      assert File.exists?(Path.join(tmp_dir, "claude"))
    end

    test "returns info map when return_info: true", %{tmp_dir: tmp_dir} do
      expect(Mock, :cmd, fn "bash", ["-c", _], opts ->
        env = Keyword.get(opts, :env, [])
        home = Enum.find_value(env, fn {"HOME", v} -> v end)
        bin_dir = Path.join([home, ".local", "bin"])
        File.mkdir_p!(bin_dir)
        binary_path = Path.join(bin_dir, "claude")
        File.write!(binary_path, "mock-binary-content")
        File.chmod!(binary_path, 0o755)
        {"Installation complete", 0}
      end)

      expect(Mock, :cmd, fn _path, ["--version"], _opts ->
        {"3.0.0 (Claude Code)", 0}
      end)

      assert {:ok, info} = Installer.install!(return_info: true)
      assert info.version == "3.0.0"
      assert info.path == Path.join(tmp_dir, "claude")
      assert is_integer(info.size_bytes)
    end

    test "passes version to install script" do
      expect(Mock, :cmd, fn "bash", ["-c", script_cmd], opts ->
        assert script_cmd =~ "bash -s -- 1.2.3"

        env = Keyword.get(opts, :env, [])
        home = Enum.find_value(env, fn {"HOME", v} -> v end)
        bin_dir = Path.join([home, ".local", "bin"])
        File.mkdir_p!(bin_dir)
        binary_path = Path.join(bin_dir, "claude")
        File.write!(binary_path, "binary")
        File.chmod!(binary_path, 0o755)
        {"OK", 0}
      end)

      expect(Mock, :cmd, fn _path, ["--version"], _opts ->
        {"1.2.3 (Claude Code)", 0}
      end)

      assert :ok = Installer.install!(version: "1.2.3")
    end

    test "raises when install script fails" do
      expect(Mock, :cmd, fn "bash", ["-c", _], _opts ->
        {"Error: network failure", 1}
      end)

      assert_raise RuntimeError, ~r/install script exited with code 1/, fn ->
        Installer.install!()
      end
    end

    test "raises when binary not found after successful script" do
      expect(Mock, :cmd, fn "bash", ["-c", _], _opts ->
        # Script "succeeds" but doesn't place a binary anywhere
        {"OK", 0}
      end)

      assert_raise RuntimeError, ~r/Failed to install Claude CLI/, fn ->
        Installer.install!()
      end
    end
  end
end
