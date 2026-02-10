defmodule ClaudeCode.Hook.Registry do
  @moduledoc false

  defstruct callbacks: %{}, can_use_tool: nil

  @doc """
  Builds a registry from the `:hooks` map and `:can_use_tool` callback.

  Returns `{registry, wire_format_hooks}` where `wire_format_hooks` is
  the map to include in the initialize handshake (or nil if no hooks).
  """
  @spec new(map() | nil, module() | function() | nil) :: {%__MODULE__{}, map() | nil}
  def new(nil, can_use_tool) do
    {%__MODULE__{can_use_tool: can_use_tool}, nil}
  end

  def new(hooks_map, can_use_tool) when hooks_map == %{} do
    {%__MODULE__{can_use_tool: can_use_tool}, nil}
  end

  def new(hooks_map, can_use_tool) when is_map(hooks_map) do
    {callbacks, wire_format, _counter} =
      Enum.reduce(hooks_map, {%{}, %{}, 0}, fn {event_name, matchers}, {cb_acc, wire_acc, counter} ->
        {matcher_entries, new_cb_acc, new_counter} =
          Enum.reduce(matchers, {[], cb_acc, counter}, fn matcher_config, {entries, cbs, cnt} ->
            hook_list = Map.get(matcher_config, :hooks, [])

            {ids, updated_cbs, updated_cnt} =
              Enum.reduce(hook_list, {[], cbs, cnt}, fn hook, {id_acc, cb, c} ->
                id = "hook_#{c}"
                {id_acc ++ [id], Map.put(cb, id, hook), c + 1}
              end)

            entry =
              maybe_put_timeout(
                %{"matcher" => Map.get(matcher_config, :matcher), "hookCallbackIds" => ids},
                Map.get(matcher_config, :timeout)
              )

            {entries ++ [entry], updated_cbs, updated_cnt}
          end)

        event_key = to_string(event_name)
        {new_cb_acc, Map.put(wire_acc, event_key, matcher_entries), new_counter}
      end)

    wire = if wire_format == %{}, do: nil, else: wire_format

    {%__MODULE__{callbacks: callbacks, can_use_tool: can_use_tool}, wire}
  end

  @doc """
  Looks up a callback by its ID.
  """
  @spec lookup(%__MODULE__{}, String.t()) :: {:ok, module() | function()} | :error
  def lookup(%__MODULE__{callbacks: callbacks}, callback_id) do
    Map.fetch(callbacks, callback_id)
  end

  defp maybe_put_timeout(entry, nil), do: entry
  defp maybe_put_timeout(entry, timeout), do: Map.put(entry, "timeout", timeout)
end
