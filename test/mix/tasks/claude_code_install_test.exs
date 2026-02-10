defmodule Mix.Tasks.ClaudeCode.InstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mox

  alias ClaudeCode.Adapter.Local.Installer
  alias ClaudeCode.SystemCmd.Mock
  alias Mix.Tasks.ClaudeCode.Install

  setup :verify_on_exit!

  describe "run/1 option parsing" do
    test "parses --version flag" do
      {opts, _args} =
        OptionParser.parse!(["--version", "2.0.0"],
          strict: [version: :string, force: :boolean]
        )

      assert opts[:version] == "2.0.0"
    end

    test "parses --force flag" do
      {opts, _args} =
        OptionParser.parse!(["--force"],
          strict: [version: :string, force: :boolean]
        )

      assert opts[:force] == true
    end

    test "parses combined flags" do
      {opts, _args} =
        OptionParser.parse!(
          ["--version", "2.0.0", "--force"],
          strict: [version: :string, force: :boolean]
        )

      assert opts[:version] == "2.0.0"
      assert opts[:force] == true
    end
  end

  describe "run/1 without --force" do
    test "shows up-to-date message when version matches" do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_task_test2_#{:erlang.unique_integer()}")
      bundled_path = Path.join(tmp_dir, "claude")

      original_cli_dir = Application.get_env(:claude_code, :cli_dir)
      expected_version = Installer.configured_version()

      try do
        File.mkdir_p!(tmp_dir)

        File.write!(bundled_path, """
        #!/bin/bash
        echo "#{expected_version} (Claude Code)"
        """)

        File.chmod!(bundled_path, 0o755)

        Application.put_env(:claude_code, :cli_dir, tmp_dir)

        # version_of calls SystemCmd.cmd to check the version
        stub(Mock, :cmd, fn command, args, opts ->
          System.cmd(command, args, opts)
        end)

        Application.put_env(:claude_code, :system_cmd_module, Mock)

        output =
          capture_io(fn ->
            Install.run([])
          end)

        assert output =~ "already installed"
        assert output =~ expected_version
      after
        if original_cli_dir do
          Application.put_env(:claude_code, :cli_dir, original_cli_dir)
        else
          Application.delete_env(:claude_code, :cli_dir)
        end

        Application.delete_env(:claude_code, :system_cmd_module)
        File.rm_rf(tmp_dir)
      end
    end

    test "auto-updates when version mismatches" do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_task_test3_#{:erlang.unique_integer()}")
      bundled_path = Path.join(tmp_dir, "claude")
      expected_version = Installer.configured_version()

      original_cli_dir = Application.get_env(:claude_code, :cli_dir)

      try do
        File.mkdir_p!(tmp_dir)

        File.write!(bundled_path, """
        #!/bin/bash
        echo "0.0.1 (Claude Code)"
        """)

        File.chmod!(bundled_path, 0o755)

        Application.put_env(:claude_code, :cli_dir, tmp_dir)
        Application.put_env(:claude_code, :system_cmd_module, Mock)

        # First call: version_of checks the existing binary (returns old version)
        expect(Mock, :cmd, fn ^bundled_path, ["--version"], _opts ->
          {"0.0.1 (Claude Code)", 0}
        end)

        # Second call: install script execution
        expect(Mock, :cmd, fn "bash", ["-c", script_cmd], opts ->
          assert script_cmd =~ "curl -fsSL"

          env = Keyword.get(opts, :env, [])
          home = Enum.find_value(env, fn {"HOME", v} -> v end)
          bin_dir = Path.join([home, ".local", "bin"])
          File.mkdir_p!(bin_dir)
          File.write!(Path.join(bin_dir, "claude"), "binary")
          File.chmod!(Path.join(bin_dir, "claude"), 0o755)
          {"OK", 0}
        end)

        # Third call: version_from_binary after install
        expect(Mock, :cmd, fn ^bundled_path, ["--version"], _opts ->
          {"#{expected_version} (Claude Code)", 0}
        end)

        output =
          capture_io(fn ->
            Install.run([])
          end)

        assert output =~ "version mismatch"
        assert output =~ "v0.0.1 installed"
      after
        if original_cli_dir do
          Application.put_env(:claude_code, :cli_dir, original_cli_dir)
        else
          Application.delete_env(:claude_code, :cli_dir)
        end

        Application.delete_env(:claude_code, :system_cmd_module)
        File.rm_rf(tmp_dir)
      end
    end
  end
end
