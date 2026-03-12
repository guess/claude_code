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
      {:ok, cli_path} ->
        # The CLI uses Ink which requires a TTY with raw mode support.
        # We use `script` to allocate a PTY and spawn via :erlang.open_port
        # to avoid Elixir's IO system choking on raw terminal escape codes.
        script = System.find_executable("script")

        unless script do
          Mix.shell().error("""
          `script` command not found. Run the CLI directly instead:
            #{cli_path} setup-token
          """)

          exit({:shutdown, 1})
        end

        # macOS and Linux `script` have different flag syntax
        {wrapper, args} =
          case :os.type() do
            {:unix, :darwin} ->
              {script, ["-q", "/dev/null", cli_path, "setup-token"]}

            {:unix, _} ->
              {script, ["-qc", "#{cli_path} setup-token", "/dev/null"]}
          end

        port =
          Port.open({:spawn_executable, wrapper}, [
            :binary,
            :exit_status,
            :nouse_stdio,
            {:args, args}
          ])

        wait_for_exit(port)

      {:error, _reason} ->
        Mix.shell().error("""
        Claude CLI not found.

        Install it with: mix claude_code.install
        Or configure: config :claude_code, cli_path: :global
        """)

        exit({:shutdown, 1})
    end
  end

  defp wait_for_exit(port) do
    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, code}} -> exit({:shutdown, code})
      {^port, _} -> wait_for_exit(port)
    end
  end
end
