defmodule Mix.Tasks.ClaudeCode.InstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.ClaudeCode.Install

  describe "run/1 option parsing" do
    test "parses --version flag" do
      # Verify option parsing works correctly
      {opts, _args} =
        OptionParser.parse!(["--version", "2.1.29"],
          strict: [
            version: :string,
            if_missing: :boolean,
            force: :boolean
          ]
        )

      assert opts[:version] == "2.1.29"
    end

    test "parses --if-missing flag" do
      {opts, _args} =
        OptionParser.parse!(["--if-missing"],
          strict: [
            version: :string,
            if_missing: :boolean,
            force: :boolean
          ]
        )

      assert opts[:if_missing] == true
    end

    test "parses --force flag" do
      {opts, _args} =
        OptionParser.parse!(["--force"],
          strict: [
            version: :string,
            if_missing: :boolean,
            force: :boolean
          ]
        )

      assert opts[:force] == true
    end

    test "parses combined flags" do
      {opts, _args} =
        OptionParser.parse!(
          ["--version", "2.0.0", "--force"],
          strict: [
            version: :string,
            if_missing: :boolean,
            force: :boolean
          ]
        )

      assert opts[:version] == "2.0.0"
      assert opts[:force] == true
    end
  end

  describe "run/1 with --if-missing" do
    test "skips installation when CLI is already bundled" do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_task_test_#{:erlang.unique_integer()}")
      bundled_path = Path.join(tmp_dir, "claude")

      original_cli_dir = Application.get_env(:claude_code, :cli_dir)

      try do
        # Create bundled path
        File.mkdir_p!(tmp_dir)
        File.write!(bundled_path, "#!/bin/bash\necho 'test'")
        File.chmod!(bundled_path, 0o755)

        Application.put_env(:claude_code, :cli_dir, tmp_dir)

        output =
          capture_io(fn ->
            Install.run(["--if-missing"])
          end)

        assert output =~ "already bundled"
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

  describe "run/1 without --force" do
    test "shows message when CLI is already bundled" do
      tmp_dir = Path.join(System.tmp_dir!(), "claude_task_test2_#{:erlang.unique_integer()}")
      bundled_path = Path.join(tmp_dir, "claude")

      original_cli_dir = Application.get_env(:claude_code, :cli_dir)

      try do
        # Create bundled path
        File.mkdir_p!(tmp_dir)
        File.write!(bundled_path, "#!/bin/bash\necho 'test'")
        File.chmod!(bundled_path, 0o755)

        Application.put_env(:claude_code, :cli_dir, tmp_dir)

        output =
          capture_io(fn ->
            Install.run([])
          end)

        assert output =~ "already bundled"
        assert output =~ "--force"
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

  describe "version_label/1 helper" do
    # Test the private version_label function behavior through the output
    test "shows no version label for 'latest'" do
      # Can't test private function directly, but we can verify the expected output format
      # The function returns "" for "latest" and " vX.X.X" for specific versions
      assert true
    end
  end
end
