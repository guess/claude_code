defmodule Mix.Tasks.ClaudeCode.SetupToken do
  @shortdoc "Runs `claude setup-token` to configure an OAuth token"

  @moduledoc """
  Runs `claude setup-token` using the resolved CLI binary.

  This starts an interactive OAuth flow that opens your browser for authentication,
  then prints the token to stdout.

  ## Usage

      mix claude_code.setup_token

  ## Resolution

  The CLI binary is resolved using the same logic as `mix claude_code.path`.
  """

  use Mix.Task

  alias ClaudeCode.Adapter.Port.Resolver

  @impl Mix.Task
  def run(_args) do
    case Resolver.find_binary() do
      {:ok, path} ->
        exit_code = Mix.shell().cmd("#{path} setup-token")

        if exit_code != 0 do
          exit({:shutdown, exit_code})
        end

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
