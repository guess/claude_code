defmodule ClaudeCode.Plugin.CLI do
  @moduledoc false

  alias ClaudeCode.Adapter.Port.Resolver

  @doc """
  Runs a `claude` CLI command and parses the output.

  Resolves the CLI binary via `ClaudeCode.Adapter.Port.Resolver`, executes the
  command through `ClaudeCode.System`, and applies the parse function on success.
  Returns `{:error, output}` on non-zero exit codes.
  """
  @spec run(
          args :: [String.t()],
          opts :: keyword(),
          parse_fn :: (String.t() -> {:ok, term()} | {:error, String.t()})
        ) :: {:ok, term()} | {:error, term()}
  def run(args, opts, parse_fn) do
    with {:ok, binary} <- Resolver.find_binary(opts) do
      case ClaudeCode.System.cmd(binary, args, stderr_to_stdout: true) do
        {output, 0} -> parse_fn.(output)
        {error_output, _exit_code} -> {:error, String.trim(error_output)}
      end
    end
  end

  @doc """
  Builds `--scope <scope>` args from opts.
  """
  @spec scope_args(keyword()) :: [String.t()]
  def scope_args(opts) do
    case Keyword.get(opts, :scope) do
      nil -> []
      scope -> ["--scope", to_string(scope)]
    end
  end

  @doc """
  Wraps trimmed output in an ok tuple.
  """
  @spec ok_trimmed(String.t()) :: {:ok, String.t()}
  def ok_trimmed(output), do: {:ok, String.trim(output)}
end
