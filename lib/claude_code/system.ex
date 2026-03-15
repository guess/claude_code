defmodule ClaudeCode.System do
  @moduledoc false

  @doc "Behaviour for wrapping System.cmd/3, allowing test mocking."
  @callback cmd(binary(), [binary()], keyword()) :: {binary(), non_neg_integer()}

  def cmd(command, args, opts \\ []) do
    impl().cmd(command, args, opts)
  end

  defp impl do
    case Application.get_env(:claude_code, ClaudeCode.System) do
      nil -> impl_from_adapter()
      module -> module
    end
  end

  defp impl_from_adapter do
    case Application.get_env(:claude_code, :adapter) do
      {ClaudeCode.Adapter.Node, _} -> ClaudeCode.System.Remote
      _ -> ClaudeCode.System.Default
    end
  end
end
