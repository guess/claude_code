defmodule ClaudeCode.Hook.Registry do
  @moduledoc false

  @type t :: %__MODULE__{}

  defstruct callbacks: %{}, targets: %{}, can_use_tool: nil

  @doc """
  Builds a registry from the `:hooks` map.

  Returns `{registry, wire_format_hooks}` where `wire_format_hooks` is
  the map to include in the initialize handshake (or nil if no hooks).
  """
  @spec new(map() | nil, term()) :: {%__MODULE__{}, map() | nil}
  def new(hooks_map, can_use_tool \\ nil)
  def new(nil, can_use_tool), do: {%__MODULE__{can_use_tool: can_use_tool}, nil}
  def new(hooks_map, can_use_tool) when hooks_map == %{}, do: {%__MODULE__{can_use_tool: can_use_tool}, nil}

  def new(hooks_map, can_use_tool) when is_map(hooks_map) do
    state = %{callbacks: %{}, targets: %{}, counter: 0}

    {wire_format, state} =
      Enum.map_reduce(hooks_map, state, fn {event_name, matcher_list}, acc ->
        {entries, acc} = Enum.map_reduce(matcher_list, acc, &register_matcher/2)
        {{to_string(event_name), entries}, acc}
      end)

    wire = Map.new(wire_format)
    wire = if wire == %{}, do: nil, else: wire

    {%__MODULE__{
       callbacks: state.callbacks,
       targets: state.targets,
       can_use_tool: can_use_tool
     }, wire}
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

    {
      %__MODULE__{callbacks: Map.new(local_cbs), targets: Map.new(local_tgts), can_use_tool: registry.can_use_tool},
      %__MODULE__{callbacks: Map.new(remote_cbs), targets: Map.new(remote_tgts)}
    }
  end

  defp register_matcher(matcher_config, acc) do
    config = normalize_matcher(matcher_config)
    hook_list = Map.get(config, :hooks, [])
    where = Map.get(config, :where, :local)

    {ids, acc} =
      Enum.map_reduce(hook_list, acc, fn hook, %{counter: c} = acc ->
        id = "hook_#{c}"

        acc = %{
          acc
          | callbacks: Map.put(acc.callbacks, id, hook),
            targets: Map.put(acc.targets, id, where),
            counter: c + 1
        }

        {id, acc}
      end)

    entry = %{"matcher" => Map.get(config, :matcher), "hookCallbackIds" => ids}
    entry = maybe_put_timeout(entry, Map.get(config, :timeout))

    {entry, acc}
  end

  defp normalize_matcher(hook) when is_atom(hook), do: %{hooks: [hook]}
  defp normalize_matcher(hook) when is_function(hook, 2), do: %{hooks: [hook]}
  defp normalize_matcher(%{} = config), do: config

  defp maybe_put_timeout(entry, nil), do: entry
  defp maybe_put_timeout(entry, timeout), do: Map.put(entry, "timeout", timeout)
end
