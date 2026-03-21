defmodule ClaudeCode.Case do
  @moduledoc """
  Test case template for ClaudeCode tests that need System mock or app config management.

  ## Tags

  ### `@moduletag :mock_system` / `@tag :mock_system`

  Sets up `ClaudeCode.System.Mock` and a valid `cli_path` so that `Plugin.CLI.run/3`
  and `Resolver.find_binary/1` work without a real CLI binary. Auto-cleanup on exit.

      describe "plugin commands" do
        @describetag :mock_system

        test "lists plugins", %{cli_path: cli_path} do
          expect(ClaudeCode.System.Mock, :cmd, fn _binary, _args, _opts -> {"[]", 0} end)
          assert {:ok, []} = Plugin.list()
        end
      end

  ### `@moduletag :real_system` / `@tag :real_system`

  Ensures `ClaudeCode.System` is NOT mocked — clears any mock set by other async tests.
  Use this when testing code that must call real `System.find_executable/1` or `System.cmd/3`.

      @tag :real_system
      test "finds real binary" do
        # Uses real System, not mock
      end
  """

  use ExUnit.CaseTemplate

  @cli_path System.find_executable("true")

  using do
    quote do
      import Mox
    end
  end

  setup tags do
    if tags[:mock_system] do
      setup_mock_system()
    end

    if tags[:real_system] do
      setup_real_system()
    end

    :ok
  end

  defp setup_mock_system do
    Application.put_env(:claude_code, ClaudeCode.System, ClaudeCode.System.Mock)
    Application.put_env(:claude_code, :cli_path, @cli_path)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:claude_code, ClaudeCode.System)
      Application.put_env(:claude_code, :cli_path, "/nonexistent/test/claude")
    end)
  end

  defp setup_real_system do
    prev = Application.get_env(:claude_code, ClaudeCode.System)
    Application.delete_env(:claude_code, ClaudeCode.System)

    ExUnit.Callbacks.on_exit(fn ->
      if prev do
        Application.put_env(:claude_code, ClaudeCode.System, prev)
      end
    end)
  end
end
