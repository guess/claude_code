defmodule ClaudeCode.Sandbox.Helpers do
  @moduledoc false

  @doc """
  Normalizes a map with atom, snake_case string, or camelCase string keys
  into a keyword list containing only keys present in `valid_fields`.
  """
  @spec normalize_map_keys(map(), [atom()]) :: keyword()
  def normalize_map_keys(map, valid_fields) do
    Enum.reduce(map, [], fn {key, value}, acc ->
      atom_key = to_atom_key(key)
      if atom_key in valid_fields, do: [{atom_key, value} | acc], else: acc
    end)
  end

  @spec to_atom_key(atom() | String.t()) :: atom() | nil
  defp to_atom_key(key) when is_atom(key), do: key

  defp to_atom_key(key) when is_binary(key) do
    :erlang.binary_to_existing_atom(Macro.underscore(key), :utf8)
  catch
    :error, :badarg -> nil
  end
end
