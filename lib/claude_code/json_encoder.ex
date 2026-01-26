defmodule ClaudeCode.JSONEncoder do
  @moduledoc """
  Shared JSON encoding logic for ClaudeCode structs.

  Converts structs to maps with nil values removed for clean JSON output.
  Used by both Jason.Encoder and JSON.Encoder protocol implementations.
  """

  @doc """
  Converts a struct to an encodable map, excluding nil values.

  Handles nested structs, maps, and lists recursively.

  ## Examples

      iex> block = %ClaudeCode.Content.TextBlock{type: :text, text: "hello"}
      iex> ClaudeCode.JSONEncoder.to_encodable(block)
      %{type: :text, text: "hello"}

      iex> msg = %ClaudeCode.Message.ResultMessage{result: nil, is_error: false, ...}
      iex> ClaudeCode.JSONEncoder.to_encodable(msg)
      %{is_error: false, ...}  # result key excluded

  """
  @spec to_encodable(struct()) :: map()
  def to_encodable(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> drop_nils()
  end

  defp drop_nils(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {k, process_value(v)} end)
  end

  defp process_value(%{__struct__: _} = struct), do: to_encodable(struct)
  defp process_value(map) when is_map(map), do: drop_nils(map)
  defp process_value(list) when is_list(list), do: Enum.map(list, &process_value/1)
  defp process_value(other), do: other
end
