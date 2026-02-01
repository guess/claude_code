defmodule ClaudeCode.CLI do
  @moduledoc """
  Handles CLI subprocess management for Claude Code.

  This module is responsible for:
  - Finding the claude binary
  - Building command arguments from validated options
  - Managing the subprocess lifecycle

  ## Binary Resolution

  The CLI binary is resolved in the following order:

  1. `:cli_path` option passed to the function
  2. Application config `:cli_path`
  3. Bundled binary in `cli_dir` (default: priv/bin/)
  4. System PATH via `System.find_executable/1`
  5. Common installation locations (npm, yarn, home directory)

  If not found, an error is returned with installation instructions.
  """

  alias ClaudeCode.Installer
  alias ClaudeCode.Options

  @required_flags ["--output-format", "stream-json", "--verbose", "--print"]

  @doc """
  Finds the claude binary using multiple resolution strategies.

  ## Options

  - `:cli_path` - Explicit path to the CLI binary (highest priority)

  ## Resolution Order

  1. `:cli_path` option (if provided)
  2. Application config `:cli_path`
  3. Bundled binary in `cli_dir`
  4. System PATH
  5. Common installation locations

  Returns `{:ok, path}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> ClaudeCode.CLI.find_binary()
      {:ok, "/usr/local/bin/claude"}

      iex> ClaudeCode.CLI.find_binary(cli_path: "/custom/path/claude")
      {:ok, "/custom/path/claude"}
  """
  @spec find_binary(keyword()) :: {:ok, String.t()} | {:error, :not_found}
  def find_binary(opts \\ []) do
    cli_path = Keyword.get(opts, :cli_path)

    cond do
      # 1. Explicit cli_path option
      cli_path && File.exists?(cli_path) ->
        {:ok, cli_path}

      cli_path ->
        # cli_path was provided but doesn't exist
        {:error, :not_found}

      # 2-5. Delegate to Installer for remaining resolution
      true ->
        Installer.bin_path()
    end
  end

  @doc """
  Builds the command and arguments for running the Claude CLI.

  Accepts validated options from the Options module and converts them to CLI flags.
  If a session_id is provided, automatically adds --resume flag for session continuity.

  ## Options

  - `:cli_path` - Explicit path to the CLI binary

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
    end
  end

  @doc """
  Validates that the Claude CLI is properly installed and accessible.

  ## Options

  - `:cli_path` - Explicit path to the CLI binary
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
    end
  end

  # Private Functions

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
    """
    Claude CLI not found.

    Install it using one of these methods:

    1. Run the mix task:
       mix claude_code.install

    2. Install manually:
       curl -fsSL https://claude.ai/install.sh | bash

    3. Configure an explicit path:
       config :claude_code, cli_path: "/path/to/claude"

    For more information, visit: https://docs.anthropic.com/en/docs/claude-code
    """
  end
end
