defmodule Mix.Tasks.ClaudeCode.Uninstall do
  @shortdoc "Removes the bundled Claude CLI binary"

  @moduledoc """
  Removes the bundled Claude CLI binary.

  ## Usage

      mix claude_code.uninstall

  This removes the CLI binary from `priv/bin/` (or the configured `:cli_dir`).
  It does not affect globally installed CLIs (`:global` or explicit path configurations).

  ## Examples

      # Remove the bundled CLI
      mix claude_code.uninstall

  ## Reinstalling

  To reinstall after uninstalling:

      mix claude_code.install
  """

  use Mix.Task

  alias ClaudeCode.Adapter.Local.Installer

  @impl Mix.Task
  def run(_args) do
    bundled_path = Installer.bundled_path()

    if File.exists?(bundled_path) do
      File.rm!(bundled_path)
      Mix.shell().info("Removed Claude CLI at #{bundled_path}")
    else
      Mix.shell().info("No bundled Claude CLI found at #{bundled_path}")
    end
  end
end
