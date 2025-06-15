defmodule ClaudeCode.CLI do
  @moduledoc """
  Handles CLI subprocess management for Claude Code.

  This module is responsible for:
  - Finding the claude binary
  - Building command arguments from validated options
  - Managing the subprocess lifecycle
  """

  alias ClaudeCode.Options

  @claude_binary "claude"
  @required_flags ["--output-format", "stream-json", "--verbose", "--print"]

  @doc """
  Finds the claude binary in the system PATH.

  Returns `{:ok, path}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find_binary() :: {:ok, String.t()} | {:error, :not_found}
  def find_binary do
    case System.find_executable(@claude_binary) do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  @doc """
  Builds the command and arguments for running the Claude CLI.

  Accepts validated options from the Options module and converts them to CLI flags.

  Returns `{:ok, {executable, args}}` or `{:error, reason}`.
  """
  @spec build_command(String.t(), String.t(), keyword()) ::
          {:ok, {String.t(), [String.t()]}} | {:error, term()}
  def build_command(prompt, _api_key, opts) do
    case find_binary() do
      {:ok, executable} ->
        args = build_args(prompt, opts)
        {:ok, {executable, args}}

      {:error, :not_found} ->
        {:error, {:cli_not_found, cli_not_found_message()}}
    end
  end

  @doc """
  Validates that the Claude CLI is properly installed and accessible.
  """
  @spec validate_installation() :: :ok | {:error, term()}
  def validate_installation do
    case find_binary() do
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

  defp build_args(prompt, opts) do
    # Start with required flags
    base_args = @required_flags

    # Convert options to CLI flags using Options module
    option_args = Options.to_cli_args(opts)

    # Combine all arguments and append the prompt
    base_args ++ option_args ++ [prompt]
  end

  defp cli_not_found_message do
    """
    Claude CLI not found in PATH.

    Please install Claude Code CLI:
    1. Visit https://claude.ai/code
    2. Follow the installation instructions for your platform
    3. Ensure 'claude' is available in your PATH

    You can verify the installation by running: claude --version
    """
  end
end
