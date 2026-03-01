defmodule Mix.Tasks.ClaudeCode.Path do
  @shortdoc "Prints the path to the resolved Claude CLI binary"

  @moduledoc """
  Prints the path to the resolved Claude CLI binary.

  This is useful for running the CLI directly, e.g., for authentication:

      $(mix claude_code.path) /login

  ## Usage

      mix claude_code.path

  ## Resolution

  The path is resolved based on the `:cli_path` configuration:

  - `:bundled` (default) — Uses the binary in `priv/bin/`, auto-installs if missing
  - `:global` — Finds the system-installed `claude` binary
  - `"/path/to/claude"` — Uses the explicit path

  Configure via application config:

      config :claude_code, cli_path: :global
  """

  use Mix.Task

  alias ClaudeCode.Adapter.Port.Resolver

  @impl Mix.Task
  def run(_args) do
    case Resolver.find_binary() do
      {:ok, path} ->
        Mix.shell().info(path)

      {:error, _reason} ->
        Mix.shell().error("""
        Claude CLI not found.

        Install it with: mix claude_code.install
        Or configure: config :claude_code, cli_path: :global
        """)

        exit({:shutdown, 1})
    end
  end
end
