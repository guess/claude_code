defmodule ClaudeCode.MapUtils do
  @moduledoc false

  @doc """
  Converts a string key to an existing atom, or returns the string unchanged.

  Uses `:erlang.binary_to_existing_atom/2` to avoid creating new atoms from
  external input. If the atom does not already exist in the atom table, the
  original string is returned.
  """
  @spec safe_atomize_key(atom()) :: atom()
  @spec safe_atomize_key(String.t()) :: atom() | String.t()
  def safe_atomize_key(key) when is_atom(key), do: key

  def safe_atomize_key(key) when is_binary(key) do
    :erlang.binary_to_existing_atom(key, :utf8)
  catch
    :error, :badarg -> key
  end

  @doc """
  Safely atomizes top-level string keys in a map.

  Known keys (already in the atom table) become atoms; unknown keys stay as strings.
  Values are not modified.
  """
  @spec safe_atomize_keys(map()) :: map()
  def safe_atomize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {safe_atomize_key(key), value} end)
  end

  @doc """
  Recursively atomizes string keys in nested maps and lists.

  Known keys become atoms; unknown keys stay as strings.
  """
  @spec safe_atomize_keys_recursive(term()) :: term()
  def safe_atomize_keys_recursive(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {safe_atomize_key(key), safe_atomize_keys_recursive(value)} end)
  end

  def safe_atomize_keys_recursive(list) when is_list(list) do
    Enum.map(list, &safe_atomize_keys_recursive/1)
  end

  def safe_atomize_keys_recursive(value), do: value
end
