defmodule ClaudeCode.Hook.Registry do
  @moduledoc false

  @type t :: %__MODULE__{}

  defstruct callbacks: %{}, targets: %{}

  @doc """
  Builds a registry from the `:hooks` map.

  Returns `{registry, wire_format_hooks}` where `wire_format_hooks` is
  the map to include in the initialize handshake (or nil if no hooks).
  """
  @spec new(map() | nil) :: {%__MODULE__{}, map() | nil}
  def new(nil) do
    {%__MODULE__{}, nil}
  end

  def new(hooks_map) when hooks_map == %{} do
    {%__MODULE__{}, nil}
  end

  def new(hooks_map) when is_map(hooks_map) do
    {callbacks, targets, wire_format, _counter} =
      Enum.reduce(hooks_map, {%{}, %{}, %{}, 0}, fn {event_name, matchers}, {cb_acc, tgt_acc, wire_acc, counter} ->
        {matcher_entries, new_cb_acc, new_tgt_acc, new_counter} =
          Enum.reduce(matchers, {[], cb_acc, tgt_acc, counter}, fn matcher_config, {entries, cbs, tgts, cnt} ->
            matcher_config = normalize_matcher(matcher_config)
            hook_list = Map.get(matcher_config, :hooks, [])
            where = Map.get(matcher_config, :where, :local)

            {ids_rev, updated_cbs, updated_tgts, updated_cnt} =
              Enum.reduce(hook_list, {[], cbs, tgts, cnt}, fn hook, {id_acc, cb, tg, c} ->
                id = "hook_#{c}"
                {[id | id_acc], Map.put(cb, id, hook), Map.put(tg, id, where), c + 1}
              end)

            entry =
              maybe_put_timeout(
                %{"matcher" => Map.get(matcher_config, :matcher), "hookCallbackIds" => Enum.reverse(ids_rev)},
                Map.get(matcher_config, :timeout)
              )

            {[entry | entries], updated_cbs, updated_tgts, updated_cnt}
          end)

        event_key = to_string(event_name)
        {new_cb_acc, new_tgt_acc, Map.put(wire_acc, event_key, Enum.reverse(matcher_entries)), new_counter}
      end)

    wire = if wire_format == %{}, do: nil, else: wire_format

    {%__MODULE__{callbacks: callbacks, targets: targets}, wire}
  end

  @doc """
  Looks up a callback by its ID.
  """
  @spec lookup(%__MODULE__{}, String.t()) :: {:ok, module() | function()} | :error
  def lookup(%__MODULE__{callbacks: callbacks}, callback_id) do
    Map.fetch(callbacks, callback_id)
  end

  @doc """
  Returns the execution target (`:local` or `:remote`) for a callback ID, or `nil` if not found.
  """
  @spec target(%__MODULE__{}, String.t()) :: :local | :remote | nil
  def target(%__MODULE__{targets: targets}, callback_id) do
    Map.get(targets, callback_id)
  end

  @doc """
  Splits the registry into `{local_registry, remote_registry}` based on execution target.
  """
  @spec split(%__MODULE__{}) :: {%__MODULE__{}, %__MODULE__{}}
  def split(%__MODULE__{} = registry) do
    {local_cbs, remote_cbs} =
      Enum.split_with(registry.callbacks, fn {id, _cb} ->
        Map.get(registry.targets, id, :local) == :local
      end)

    {local_tgts, remote_tgts} =
      Enum.split_with(registry.targets, fn {_id, where} -> where == :local end)

    local = %__MODULE__{
      callbacks: Map.new(local_cbs),
      targets: Map.new(local_tgts)
    }

    remote = %__MODULE__{
      callbacks: Map.new(remote_cbs),
      targets: Map.new(remote_tgts)
    }

    {local, remote}
  end

  defp normalize_matcher(hook) when is_atom(hook), do: %{hooks: [hook]}
  defp normalize_matcher(hook) when is_function(hook, 2), do: %{hooks: [hook]}
  defp normalize_matcher(%{} = config), do: config

  defp maybe_put_timeout(entry, nil), do: entry
  defp maybe_put_timeout(entry, timeout), do: Map.put(entry, "timeout", timeout)
end
