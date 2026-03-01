defmodule Mix.Tasks.ClaudeCode.UninstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias ClaudeCode.Adapter.Port.Installer
  alias Mix.Tasks.ClaudeCode.Uninstall

  describe "run/1" do
    test "removes bundled CLI binary" do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_uninstall_test_#{:erlang.unique_integer()}")
      bundled_path = Path.join(tmp_dir, "claude")

      original_cli_dir = Application.get_env(:claude_code, :cli_dir)

      try do
        File.mkdir_p!(tmp_dir)
        File.write!(bundled_path, "#!/bin/bash\necho test")
        File.chmod!(bundled_path, 0o755)

        Application.put_env(:claude_code, :cli_dir, tmp_dir)

        assert File.exists?(bundled_path)

        output =
          capture_io(fn ->
            Uninstall.run([])
          end)

        refute File.exists?(bundled_path)
        assert output =~ "Removed Claude CLI"
        assert output =~ bundled_path
      after
        if original_cli_dir do
          Application.put_env(:claude_code, :cli_dir, original_cli_dir)
        else
          Application.delete_env(:claude_code, :cli_dir)
        end

        File.rm_rf(tmp_dir)
      end
    end

    test "reports when no bundled CLI exists" do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_uninstall_test_#{:erlang.unique_integer()}")

      original_cli_dir = Application.get_env(:claude_code, :cli_dir)

      try do
        File.mkdir_p!(tmp_dir)
        Application.put_env(:claude_code, :cli_dir, tmp_dir)

        bundled_path = Installer.bundled_path()
        refute File.exists?(bundled_path)

        output =
          capture_io(fn ->
            Uninstall.run([])
          end)

        assert output =~ "No bundled Claude CLI found"
        assert output =~ bundled_path
      after
        if original_cli_dir do
          Application.put_env(:claude_code, :cli_dir, original_cli_dir)
        else
          Application.delete_env(:claude_code, :cli_dir)
        end

        File.rm_rf(tmp_dir)
      end
    end
  end
end
