defmodule ClaudeCode.System do
  @moduledoc false

  @doc "Behaviour for wrapping System.cmd/3, allowing test mocking."
  @callback cmd(binary(), [binary()], keyword()) :: {binary(), non_neg_integer()}

  def cmd(command, args, opts \\ []) do
    impl().cmd(command, args, opts)
  end

  defp impl do
    Application.get_env(:claude_code, ClaudeCode.System, ClaudeCode.System.Default)
  end
end
