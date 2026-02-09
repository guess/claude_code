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
      cli_path && File.exists?(cli_path) ->
        {:ok, cli_path}

      cli_path ->
        {:error, :not_found}

      path = Application.get_env(:claude_code, :cli_path) ->
        if File.exists?(path), do: {:ok, path}, else: {:error, :not_found}

      true ->
        ensure_bundled_or_fallback()
    end
  end

  # Downloads the CLI to priv/bin/ on first use if not already bundled.
  # Falls back to system PATH / common locations if install fails.
  defp ensure_bundled_or_fallback do
    bundled = Installer.bundled_path()

    if File.exists?(bundled) do
      {:ok, bundled}
    else
      case auto_install() do
        {:ok, _} = result -> result
        {:error, _} -> Installer.bin_path()
      end
    end
  end

  defp auto_install do
    Installer.install!()
    bundled = Installer.bundled_path()
    if File.exists?(bundled), do: {:ok, bundled}, else: {:error, :install_failed}
  rescue
    e ->
      require Logger
      Logger.warning("Auto-install of Claude CLI failed: #{Exception.message(e)}")
      {:error, :install_failed}
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
