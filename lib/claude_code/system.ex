defmodule ClaudeCode.System do
  @moduledoc false

  @doc "Behaviour for wrapping System.cmd/3 and System.find_executable/1, allowing test mocking."
  @callback cmd(binary(), [binary()], keyword()) :: {binary(), non_neg_integer()}
  @callback find_executable(binary()) :: String.t() | nil

  def cmd(command, args, opts \\ []) do
    impl().cmd(command, args, opts)
  end

  def find_executable(name) do
    impl().find_executable(name)
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
