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

  alias ClaudeCode.Installer
  alias ClaudeCode.Options

  require Logger

  @required_flags ["--output-format", "stream-json", "--verbose", "--print"]

  @doc """
  Finds the claude binary using the configured resolution mode.

  ## Resolution Modes

  The `:cli_path` option (or app config) determines how the binary is found:

  - `:bundled` (default) — Use priv/bin/ binary. Auto-installs if missing.
    Verifies the installed version matches `Installer.configured_version()` and
    re-installs on mismatch.
  - `:global` — Finds an existing system install via PATH or common locations.
    Does not auto-install. Returns `{:error, :not_found}` if not found.
  - `"/path/to/claude"` — Uses that exact binary. Returns `{:error, :not_found}`
    if it doesn't exist.

  ## Examples

      iex> ClaudeCode.CLI.find_binary()
      {:ok, "/path/to/priv/bin/claude"}

      iex> ClaudeCode.CLI.find_binary(cli_path: :global)
      {:ok, "/usr/local/bin/claude"}

      iex> ClaudeCode.CLI.find_binary(cli_path: "/custom/path/claude")
      {:ok, "/custom/path/claude"}
  """
  @spec find_binary(keyword()) :: {:ok, String.t()} | {:error, term()}
  def find_binary(opts \\ []) do
    mode = Keyword.get(opts, :cli_path) || Application.get_env(:claude_code, :cli_path, :bundled)

    case mode do
      :bundled -> find_bundled()
      :global -> find_global()
      path when is_binary(path) -> find_explicit(path)
    end
  end

  defp find_bundled do
    bundled = Installer.bundled_path()

    if File.exists?(bundled) do
      case check_bundled_version(bundled) do
        :ok -> {:ok, bundled}
        {:error, _} -> install_bundled()
      end
    else
      install_bundled()
    end
  end

  defp find_global do
    cond do
      path = System.find_executable("claude") -> {:ok, path}
      path = Installer.find_in_common_locations() -> {:ok, path}
      true -> {:error, :not_found}
    end
  end

  defp find_explicit(path) do
    if File.exists?(path), do: {:ok, path}, else: {:error, :not_found}
  end

  defp check_bundled_version(path) do
    expected = Installer.configured_version()

    case Installer.version_of(path) do
      {:ok, ^expected} -> :ok
      {:ok, _other} -> {:error, :version_mismatch}
      {:error, _} -> {:error, :version_check_failed}
    end
  end

  defp install_bundled do
    Installer.install!()
    bundled = Installer.bundled_path()
    if File.exists?(bundled), do: {:ok, bundled}, else: {:error, :install_failed}
  rescue
    e ->
      Logger.warning("Auto-install of Claude CLI failed: #{Exception.message(e)}")
      {:error, :install_failed}
  end

  @doc """
  Builds the command and arguments for running the Claude CLI.

  Accepts validated options from the Options module and converts them to CLI flags.
  If a session_id is provided, automatically adds --resume flag for session continuity.

  Returns `{:ok, {executable, args}}` or `{:error, reason}`.
  """
  @spec build_command(String.t(), String.t(), keyword(), String.t() | nil) ::
          {:ok, {String.t(), [String.t()]}} | {:error, term()}
  def build_command(prompt, _api_key, opts, session_id \\ nil) do
    case find_binary(opts) do
      {:ok, executable} ->
        args = build_args(prompt, opts, session_id)
        {:ok, {executable, args}}

      {:error, :not_found} ->
        {:error, {:cli_not_found, cli_not_found_message()}}

      {:error, reason} ->
        {:error, {:cli_not_found, "CLI resolution failed: #{inspect(reason)}"}}
    end
  end

  @doc """
  Validates that the Claude CLI is properly installed and accessible.
  """
  @spec validate_installation(keyword()) :: :ok | {:error, term()}
  def validate_installation(opts \\ []) do
    case find_binary(opts) do
      {:ok, path} ->
        # Try to run claude --version to verify it's working
        case System.cmd(path, ["--version"], stderr_to_stdout: true) do
          {output, 0} ->
            if String.contains?(output, "Claude Code") do
              :ok
            else
              {:error, {:invalid_binary, "Binary at #{path} does not appear to be Claude CLI"}}
            end

          {error_output, _exit_code} ->
            {:error, {:cli_error, error_output}}
        end

      {:error, :not_found} ->
        {:error, {:cli_not_found, cli_not_found_message()}}

      {:error, reason} ->
        {:error, {:cli_not_found, "CLI resolution failed: #{inspect(reason)}"}}
    end
  end

  defp build_args(prompt, opts, session_id) do
    # Start with required flags
    base_args = @required_flags

    # Add resume flag if session_id is provided
    resume_args =
      if session_id do
        ["--resume", session_id]
      else
        []
      end

    # Convert options to CLI flags using Options module
    option_args = Options.to_cli_args(opts)

    # Combine all arguments: base flags, resume (if any), options, then prompt
    base_args ++ resume_args ++ option_args ++ [prompt]
  end

  defp cli_not_found_message do
    Installer.cli_not_found_message()
  end
end
