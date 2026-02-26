defmodule ClaudeCode.Session do
  @moduledoc """
  GenServer that manages Claude Code sessions.

  Each session maintains a connection to Claude (via an adapter) and handles
  request queuing, subscriber management, and session continuity.

  The session uses adapters for communication:
  - `ClaudeCode.Adapter.Local` (default) - Manages a CLI subprocess via Port
  - `ClaudeCode.Adapter.Test` - Delivers mock messages for testing
  """

  use GenServer

  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Options

  require Logger

  defstruct [
    :session_options,
    :session_id,
    # Adapter
    :adapter_module,
    :adapter_opts,
    :adapter_pid,
    # Request tracking
    :requests,
    :query_queue,
    # Caller chain for test adapter stub lookup
    :callers,
    # Adapter status (fields with defaults must come last)
    adapter_status: :provisioning
  ]

  @default_request_timeout 300_000

  # Request tracking structure
  defmodule Request do
    @moduledoc false
    defstruct [
      :id,
      :subscribers,
      :messages,
      :status,
      :created_at
    ]
  end

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a new session GenServer.

  The session eagerly starts the adapter process during init.
  """
  def start_link(opts) do
    {name, session_opts} = Keyword.pop(opts, :name)
    {_id, session_opts} = Keyword.pop(session_opts, :id)

    # Apply app config defaults and validate options early
    opts_with_config = Options.apply_app_config_defaults(session_opts)

    case Options.validate_session_options(opts_with_config) do
      {:ok, validated_opts} ->
        # Capture the caller chain for test adapter stub lookup
        callers = [self() | Process.get(:"$callers") || []]
        init_opts = validated_opts |> Keyword.put(:name, name) |> Keyword.put(:callers, callers)

        case name do
          nil -> GenServer.start_link(__MODULE__, init_opts)
          _ -> GenServer.start_link(__MODULE__, init_opts, name: name)
        end

      {:error, validation_error} ->
        raise ArgumentError, Exception.message(validation_error)
    end
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(validated_opts) do
    callers = Keyword.get(validated_opts, :callers, [])
    {adapter_module, adapter_opts} = resolve_adapter(validated_opts, callers)

    state = %__MODULE__{
      session_options: validated_opts,
      session_id: Keyword.get(validated_opts, :resume),
      adapter_module: adapter_module,
      adapter_opts: adapter_opts,
      adapter_pid: nil,
      requests: %{},
      query_queue: :queue.new(),
      callers: callers
    }

    # Eagerly start the adapter
    case adapter_module.start_link(self(), adapter_opts) do
      {:ok, pid} ->
        {:ok, %{state | adapter_pid: pid}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:query_stream, prompt, opts}, _from, state) do
    request = %Request{
      id: make_ref(),
      subscribers: [],
      messages: [],
      status: :active,
      created_at: System.monotonic_time()
    }

    case enqueue_or_execute(request, prompt, opts, state) do
      {:ok, new_state} ->
        {:reply, {:ok, request.id}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call({:receive_next, req_ref}, from, state) do
    case Map.get(state.requests, req_ref) do
      nil ->
        {:reply, {:error, :unknown_request}, state}

      %{messages: [msg | rest]} = request ->
        updated_request = %{request | messages: rest}
        new_requests = Map.put(state.requests, req_ref, updated_request)
        {:reply, {:message, msg}, %{state | requests: new_requests}}

      %{status: :completed, messages: []} ->
        new_requests = Map.delete(state.requests, req_ref)
        {:reply, :done, %{state | requests: new_requests}}

      %{status: status, messages: []} = request when status in [:active, :queued] ->
        updated_request = %{request | subscribers: [from | request.subscribers]}
        new_requests = Map.put(state.requests, req_ref, updated_request)
        {:noreply, %{state | requests: new_requests}}
    end
  end

  def handle_call(:get_session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  def handle_call(:clear_session, _from, state) do
    {:reply, :ok, %{state | session_id: nil}}
  end

  def handle_call(:health, _from, state) do
    health = state.adapter_module.health(state.adapter_pid)
    {:reply, health, state}
  end

  def handle_call({:control, subtype, params}, _from, state) do
    if supports_control?(state.adapter_module) do
      result = state.adapter_module.send_control_request(state.adapter_pid, subtype, params)
      {:reply, result, state}
    else
      {:reply, {:error, :not_supported}, state}
    end
  end

  def handle_call(:get_server_info, _from, state) do
    if supports_control?(state.adapter_module) do
      {:reply, state.adapter_module.get_server_info(state.adapter_pid), state}
    else
      {:reply, {:error, :not_supported}, state}
    end
  end

  def handle_call(:interrupt, _from, state) do
    if function_exported?(state.adapter_module, :interrupt, 1) do
      result = state.adapter_module.interrupt(state.adapter_pid)
      {:reply, result, state}
    else
      {:reply, {:error, :not_supported}, state}
    end
  end

  @impl true
  def handle_cast({:stream_cleanup, request_ref}, state) do
    new_requests = Map.delete(state.requests, request_ref)
    {:noreply, %{state | requests: new_requests}}
  end

  # ============================================================================
  # Adapter Message Handlers
  # ============================================================================

  @impl true
  def handle_info({:adapter_status, :ready}, state) do
    new_state = %{state | adapter_status: :ready}
    {:noreply, process_next_in_queue(new_state)}
  end

  def handle_info({:adapter_status, :provisioning}, state) do
    {:noreply, %{state | adapter_status: :provisioning}}
  end

  def handle_info({:adapter_status, {:error, reason}}, state) do
    new_state = fail_queued_requests(state, {:provisioning_failed, reason})
    {:noreply, %{new_state | adapter_status: {:error, reason}}}
  end

  def handle_info({:adapter_message, request_id, message}, state) do
    # Extract session ID if present
    new_session_id = extract_session_id(message) || state.session_id

    state = %{state | session_id: new_session_id}

    # Find the request and dispatch message
    case Map.get(state.requests, request_id) do
      nil ->
        {:noreply, state}

      request ->
        updated_request = dispatch_message(message, request)
        new_requests = Map.put(state.requests, request_id, updated_request)
        {:noreply, %{state | requests: new_requests}}
    end
  end

  def handle_info({:adapter_done, request_id, _reason}, state) do
    case Map.get(state.requests, request_id) do
      nil ->
        {:noreply, state}

      request ->
        new_state = complete_request(request_id, request, state)
        {:noreply, new_state}
    end
  end

  def handle_info({:adapter_error, request_id, reason}, state) do
    case Map.get(state.requests, request_id) do
      nil ->
        {:noreply, state}

      request ->
        notify_error(request, reason)
        new_requests = Map.put(state.requests, request_id, %{request | status: :completed})
        new_state = %{state | requests: new_requests}
        {:noreply, process_next_in_queue(new_state)}
    end
  end

  def handle_info({:request_timeout, request_id}, state) do
    case Map.get(state.requests, request_id) do
      nil ->
        {:noreply, state}

      request when request.status == :active ->
        elapsed =
          System.monotonic_time(:millisecond) - System.convert_time_unit(request.created_at, :native, :millisecond)

        Logger.warning("Request #{inspect(request_id)} timed out after #{elapsed}ms")
        notify_error(request, :timeout)
        new_requests = Map.put(state.requests, request_id, %{request | status: :completed})
        {:noreply, %{state | requests: new_requests}}

      _completed ->
        {:noreply, state}
    end
  end

  def handle_info({:adapter_control_request, request_id, request}, state) do
    Logger.warning("Received unhandled control request from adapter: #{inspect(request)} (#{request_id})")

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Session unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.adapter_pid do
      state.adapter_module.stop(state.adapter_pid)
    end

    :ok
  rescue
    _ -> :ok
  end

  # ============================================================================
  # Private Functions - Adapter Management
  # ============================================================================

  defp resolve_adapter(opts, callers) do
    case Keyword.get(opts, :adapter) do
      nil ->
        # Default: CLI adapter with session opts as adapter config
        {ClaudeCode.Adapter.Local, opts}

      {ClaudeCode.Test, stub_name} ->
        # Test adapter — backward compatible
        adapter_opts = opts |> Keyword.put(:stub_name, stub_name) |> Keyword.put(:callers, callers)
        {ClaudeCode.Adapter.Test, adapter_opts}

      {module, config} when is_atom(module) and is_list(config) ->
        # New pattern: {Module, adapter_config_keyword_list}
        adapter_opts = Keyword.put(config, :callers, callers)
        {module, adapter_opts}

      {module, _name} ->
        # Legacy custom adapter pattern
        {module, opts}
    end
  end

  # ============================================================================
  # Private Functions - Request Management
  # ============================================================================

  defp enqueue_or_execute(_request, _prompt, _opts, %{adapter_status: {:error, reason}} = state) do
    {:error, {:provisioning_failed, reason}, state}
  end

  defp enqueue_or_execute(request, prompt, opts, state) do
    cond do
      state.adapter_status != :ready ->
        enqueue_request(request, prompt, opts, state)

      has_active_request?(state) ->
        enqueue_request(request, prompt, opts, state)

      true ->
        execute_request(request, prompt, opts, state)
    end
  end

  defp enqueue_request(request, prompt, opts, state) do
    queued_request = %{request | status: :queued}
    queue = :queue.in({request, prompt, opts}, state.query_queue)
    new_requests = Map.put(state.requests, request.id, queued_request)
    {:ok, %{state | query_queue: queue, requests: new_requests}}
  end

  defp has_active_request?(state) do
    Enum.any?(state.requests, fn {_ref, req} -> req.status == :active end)
  end

  defp execute_request(request, prompt, opts, state) do
    {:ok, validated_opts} = Options.validate_query_options(opts)
    merged_opts = Options.merge_options(state.session_options, validated_opts)

    # Merge session_id into opts for the adapter
    query_opts =
      if state.session_id do
        Keyword.put(merged_opts, :session_id, state.session_id)
      else
        merged_opts
      end

    case state.adapter_module.send_query(
           state.adapter_pid,
           request.id,
           prompt,
           query_opts
         ) do
      :ok ->
        request_timeout = Keyword.get(merged_opts, :request_timeout, @default_request_timeout)
        schedule_request_timeout(request.id, request_timeout)
        {:ok, %{state | requests: Map.put(state.requests, request.id, request)}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp process_next_in_queue(state) do
    case :queue.out(state.query_queue) do
      {{:value, {request, prompt, opts}}, new_queue} ->
        new_state = %{state | query_queue: new_queue}

        # Get the tracked request and update to active
        tracked_request =
          case Map.get(state.requests, request.id) do
            nil -> request
            existing -> %{existing | status: :active}
          end

        case execute_request(tracked_request, prompt, opts, new_state) do
          {:ok, updated_state} ->
            updated_state

          {:error, reason, updated_state} ->
            notify_error(tracked_request, reason)
            updated_state
        end

      {:empty, _queue} ->
        state
    end
  end

  defp fail_queued_requests(state, reason) do
    {items, empty_queue} = drain_queue(state.query_queue)

    new_requests =
      Enum.reduce(items, state.requests, fn {request, _prompt, _opts}, requests ->
        case Map.get(requests, request.id) do
          nil ->
            requests

          tracked_request ->
            notify_error(tracked_request, reason)
            Map.put(requests, request.id, %{tracked_request | status: :completed})
        end
      end)

    %{state | requests: new_requests, query_queue: empty_queue}
  end

  defp drain_queue(queue) do
    drain_queue(queue, [])
  end

  defp drain_queue(queue, acc) do
    case :queue.out(queue) do
      {{:value, item}, rest} -> drain_queue(rest, [item | acc])
      {:empty, empty} -> {Enum.reverse(acc), empty}
    end
  end

  defp schedule_request_timeout(request_id, timeout) do
    Process.send_after(self(), {:request_timeout, request_id}, timeout)
  end

  # ============================================================================
  # Private Functions - Message Handling
  # ============================================================================

  defp dispatch_message(message, request) do
    case request.subscribers do
      [subscriber | rest] ->
        GenServer.reply(subscriber, {:message, message})
        %{request | subscribers: rest}

      [] ->
        %{request | messages: request.messages ++ [message]}
    end
  end

  defp complete_request(req_ref, request, state) do
    # Notify any waiting subscribers
    Enum.each(request.subscribers, fn subscriber ->
      GenServer.reply(subscriber, :done)
    end)

    # Mark as completed
    new_requests = Map.put(state.requests, req_ref, %{request | status: :completed})
    new_state = %{state | requests: new_requests}
    process_next_in_queue(new_state)
  end

  defp notify_error(request, error) do
    Enum.each(request.subscribers, fn subscriber ->
      GenServer.reply(subscriber, {:error, error})
    end)
  end

  defp extract_session_id(%SystemMessage{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(%AssistantMessage{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(%ResultMessage{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(_), do: nil

  defp supports_control?(adapter_module) do
    function_exported?(adapter_module, :send_control_request, 3)
  end
end
