defmodule ClaudeCode.CLI do
  @moduledoc """
  Handles CLI subprocess management for Claude Code.

  This module is responsible for:
  - Finding the claude binary
  - Building command arguments from validated options
  - Managing the subprocess lifecycle

  ## Binary Resolution

  The `:cli_path` option controls how the CLI binary is found:

  - `:bundled` (default) — Uses the binary in priv/bin/. Auto-installs if missing.
    Verifies version matches the SDK's pinned version and re-installs on mismatch.
  - `:global` — Finds an existing system install via PATH or common locations. No auto-install.
  - `"/path/to/claude"` — Uses that exact binary path.

  Can also be configured via application config:

      config :claude_code, cli_path: :global
  """

  alias ClaudeCode.Adapter.Local.Installer
  alias ClaudeCode.Adapter.Local.Resolver
  alias ClaudeCode.CLI.Command

  @doc """
  Finds the claude binary using the configured resolution mode.

  See `ClaudeCode.Adapter.Local.Resolver.find_binary/1` for full documentation.
  """
  @spec find_binary(keyword()) :: {:ok, String.t()} | {:error, term()}
  def find_binary(opts \\ []), do: Resolver.find_binary(opts)

  @doc """
  Builds the command and arguments for running the Claude CLI.

  Accepts validated options from the Options module and converts them to CLI flags.
  If a session_id is provided, automatically adds --resume flag for session continuity.

  The `api_key` parameter is accepted for interface compatibility but is not used
  directly -- API keys are passed via environment variables by the adapter.

  Returns `{:ok, {executable, args}}` or `{:error, reason}`.
  """
  @spec build_command(String.t(), String.t(), keyword(), String.t() | nil) ::
          {:ok, {String.t(), [String.t()]}} | {:error, term()}
  def build_command(prompt, _api_key, opts, session_id \\ nil) do
    case Resolver.find_binary(opts) do
      {:ok, executable} ->
        args = Command.build_args(prompt, opts, session_id)
        {:ok, {executable, args}}

      {:error, :not_found} ->
        {:error, {:cli_not_found, Installer.cli_not_found_message()}}

      {:error, reason} ->
        {:error, {:cli_not_found, "CLI resolution failed: #{inspect(reason)}"}}
    end
  end

  @doc """
  Validates that the Claude CLI is properly installed and accessible.

  See `ClaudeCode.Adapter.Local.Resolver.validate_installation/1` for full documentation.
  """
  @spec validate_installation(keyword()) :: :ok | {:error, term()}
  def validate_installation(opts \\ []), do: Resolver.validate_installation(opts)
end
