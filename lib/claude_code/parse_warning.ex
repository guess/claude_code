defmodule ClaudeCode.ParseWarning do
  @moduledoc false

  use GenServer

  require Logger

  @default_max_entries 4_096

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @spec once(term(), term()) :: :ok
  def once(context, value) do
    context = normalize_context(context)
    value = normalize_value(value)

    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.call(pid, {:once, context, value})

      nil ->
        # Fallback for calls before app start (e.g., manual script usage).
        Logger.warning("Unrecognized #{context} from CLI: #{inspect(value)}")
        :ok
    end
  catch
    :exit, _ ->
      # Avoid crashing parsers if warning infra is temporarily unavailable.
      Logger.warning("Unrecognized #{context} from CLI: #{inspect(value)}")
      :ok
  end

  @doc false
  @spec reset() :: :ok
  def reset do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> GenServer.call(pid, :reset)
      nil -> :ok
    end
  end

  @doc false
  @spec stats() :: %{max_entries: pos_integer(), size: non_neg_integer()}
  def stats do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        GenServer.call(pid, :stats)

      nil ->
        %{size: 0, max_entries: configured_max_entries()}
    end
  end

  @impl true
  def init(opts) do
    max_entries =
      opts
      |> Keyword.get(:max_entries, configured_max_entries())
      |> normalize_max_entries()

    {:ok, %{seen: MapSet.new(), order: :queue.new(), size: 0, max_entries: max_entries}}
  end

  @impl true
  def handle_call({:once, context, value}, _from, state) do
    key = {context, value}

    if MapSet.member?(state.seen, key) do
      {:reply, :ok, state}
    else
      Logger.warning("Unrecognized #{context} from CLI: #{inspect(value)}")
      {:reply, :ok, add_key(state, key)}
    end
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | seen: MapSet.new(), order: :queue.new(), size: 0}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, %{size: state.size, max_entries: state.max_entries}, state}
  end

  defp add_key(state, key) do
    state
    |> Map.update!(:seen, &MapSet.put(&1, key))
    |> Map.update!(:order, &:queue.in(key, &1))
    |> Map.update!(:size, &(&1 + 1))
    |> trim_if_needed()
  end

  defp trim_if_needed(%{size: size, max_entries: max_entries} = state) when size <= max_entries do
    state
  end

  defp trim_if_needed(state) do
    {{:value, oldest_key}, order} = :queue.out(state.order)

    state
    |> Map.put(:order, order)
    |> Map.update!(:seen, &MapSet.delete(&1, oldest_key))
    |> Map.update!(:size, &(&1 - 1))
    |> trim_if_needed()
  end

  defp configured_max_entries do
    Application.get_env(:claude_code, :parse_warning_max_entries, @default_max_entries)
  end

  defp normalize_max_entries(value) when is_integer(value) and value > 0, do: value
  defp normalize_max_entries(_), do: @default_max_entries

  defp normalize_context(context) when is_binary(context), do: context
  defp normalize_context(context), do: inspect(context)

  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value), do: inspect(value)
end
