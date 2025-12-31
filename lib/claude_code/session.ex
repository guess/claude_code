defmodule ClaudeCode.Session do
  @moduledoc """
  GenServer that manages a persistent Claude Code CLI subprocess.

  Each session maintains a long-running CLI process with `--input-format stream-json`
  for bidirectional communication. All queries are sent through this persistent
  connection for efficiency and natural conversation continuity.

  The session automatically connects on start and disconnects on stop.
  """

  use GenServer

  alias ClaudeCode.CLI
  alias ClaudeCode.Message
  alias ClaudeCode.Options
  alias ClaudeCode.ToolCallback

  require Logger

  defstruct [
    :api_key,
    :model,
    :session_options,
    :session_id,
    :tool_callback,
    :pending_tool_uses,
    # CLI subprocess
    :port,
    :buffer,
    # Active requests: %{ref => %Request{}}
    :requests,
    # Query queue for serial execution
    :query_queue
  ]

  @request_timeout 300_000

  # Request tracking structure
  defmodule Request do
    @moduledoc false
    defstruct [
      :id,
      # :sync | :stream
      :type,
      # For sync requests - GenServer.from()
      :from,
      # For stream requests - list of waiting subscribers (GenServer.from())
      :subscribers,
      # Collected messages for sync requests
      :messages,
      # :active | :completed
      :status,
      :created_at
    ]
  end

  # Client API

  @doc """
  Starts a new session GenServer.

  The session automatically connects to the CLI subprocess on startup.
  """
  def start_link(opts) do
    {name, session_opts} = Keyword.pop(opts, :name)

    # Apply app config defaults and validate options early
    opts_with_config = Options.apply_app_config_defaults(session_opts)

    case Options.validate_session_options(opts_with_config) do
      {:ok, validated_opts} ->
        # Pass validated options to GenServer
        init_opts = Keyword.put(validated_opts, :name, name)

        case name do
          nil -> GenServer.start_link(__MODULE__, init_opts)
          _ -> GenServer.start_link(__MODULE__, init_opts, name: name)
        end

      {:error, validation_error} ->
        # Raise ArgumentError for invalid options
        raise ArgumentError, Exception.message(validation_error)
    end
  end

  # Server Callbacks

  @impl true
  def init(validated_opts) do
    state = %__MODULE__{
      api_key: Keyword.get(validated_opts, :api_key),
      model: Keyword.get(validated_opts, :model),
      session_options: validated_opts,
      session_id: Keyword.get(validated_opts, :resume),
      tool_callback: Keyword.get(validated_opts, :tool_callback),
      pending_tool_uses: %{},
      port: nil,
      buffer: "",
      requests: %{},
      query_queue: :queue.new()
    }

    # Lazy connect - CLI is spawned on first query
    # This allows the session to start even if CLI isn't immediately available
    {:ok, state}
  end

  @impl true
  def handle_call({:query, prompt, opts}, from, state) do
    request = %Request{
      id: make_ref(),
      type: :sync,
      from: from,
      messages: [],
      status: :active,
      created_at: System.monotonic_time()
    }

    new_state = enqueue_or_execute(request, prompt, opts, state)
    {:noreply, new_state}
  end

  def handle_call({:query_stream, prompt, opts}, _from, state) do
    request = %Request{
      id: make_ref(),
      type: :stream,
      subscribers: [],
      messages: [],
      status: :active,
      created_at: System.monotonic_time()
    }

    new_state = enqueue_or_execute(request, prompt, opts, state)
    {:reply, {:ok, request.id}, new_state}
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

      %{status: :active, messages: []} = request ->
        updated_request = %{request | subscribers: [from | request.subscribers]}
        new_requests = Map.put(state.requests, req_ref, updated_request)
        {:noreply, %{state | requests: new_requests}}
    end
  end

  def handle_call(:get_session_id, _from, state) do
    {:reply, {:ok, state.session_id}, state}
  end

  def handle_call(:clear_session, _from, state) do
    {:reply, :ok, %{state | session_id: nil}}
  end

  @impl true
  def handle_cast({:stream_cleanup, request_ref}, state) do
    new_requests = Map.delete(state.requests, request_ref)
    {:noreply, %{state | requests: new_requests}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    buffer = state.buffer <> data
    {lines, remaining_buffer} = extract_lines(buffer)

    new_state =
      Enum.reduce(lines, %{state | buffer: remaining_buffer}, fn line, acc_state ->
        process_line(line, acc_state)
      end)

    {:noreply, new_state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.debug("CLI exited with status #{status}")

    # Mark all active requests as errored
    new_requests =
      Map.new(state.requests, fn {ref, request} ->
        if request.status == :active do
          notify_error(request, {:cli_exit, status})
          {ref, %{request | status: :completed}}
        else
          {ref, request}
        end
      end)

    # Clear port and try to reconnect on next query
    new_state = %{state | port: nil, requests: new_requests, buffer: ""}

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.error("CLI port closed: #{inspect(reason)}")

    # Mark all active requests as errored
    new_requests =
      Map.new(state.requests, fn {ref, request} ->
        if request.status == :active do
          notify_error(request, {:port_closed, reason})
          {ref, %{request | status: :completed}}
        else
          {ref, request}
        end
      end)

    new_state = %{state | port: nil, requests: new_requests, buffer: ""}
    {:noreply, new_state}
  end

  def handle_info({port, :eof}, %{port: port} = state) do
    # EOF received - this is expected when stdin is closed
    {:noreply, state}
  end

  def handle_info({:request_timeout, request_id}, state) do
    case Map.get(state.requests, request_id) do
      nil ->
        {:noreply, state}

      request when request.status == :active ->
        Logger.warning("Request #{inspect(request_id)} timed out after #{@request_timeout}ms")
        notify_error(request, :timeout)
        new_requests = Map.put(state.requests, request_id, %{request | status: :completed})
        {:noreply, %{state | requests: new_requests}}

      _completed ->
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Close CLI port on shutdown
    if state.port && Port.info(state.port) do
      Port.close(state.port)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  # Private Functions

  defp enqueue_or_execute(request, prompt, opts, state) do
    # Ensure we're connected
    case ensure_connected(state) do
      {:ok, connected_state} ->
        if has_active_request?(connected_state) do
          # Queue this request
          queue = :queue.in({request, prompt, opts}, connected_state.query_queue)
          %{connected_state | query_queue: queue}
        else
          # Execute immediately
          execute_request(request, prompt, opts, connected_state)
        end

      {:error, reason, state} ->
        # Connection failed, notify the request
        notify_error(request, reason)
        state
    end
  end

  defp has_active_request?(state) do
    Enum.any?(state.requests, fn {_ref, req} -> req.status == :active end)
  end

  defp ensure_connected(%{port: nil} = state) do
    case spawn_cli(state) do
      {:ok, port} ->
        Logger.debug("Reconnected to CLI")
        {:ok, %{state | port: port, buffer: ""}}

      {:error, reason} ->
        Logger.error("Failed to reconnect: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  defp ensure_connected(state), do: {:ok, state}

  defp execute_request(request, prompt, opts, state) do
    if is_nil(state.port) do
      notify_error(request, :not_connected)
      state
    else
      # Merge options
      {:ok, validated_opts} = Options.validate_query_options(opts)
      _final_opts = Options.merge_options(state.session_options, validated_opts)

      # Send the query to CLI
      message = ClaudeCode.Input.user_message(prompt, state.session_id || "default")
      Port.command(state.port, message <> "\n")

      # Register the request and schedule timeout
      schedule_request_timeout(request.id)
      %{state | requests: Map.put(state.requests, request.id, request)}
    end
  end

  defp process_next_in_queue(state) do
    case :queue.out(state.query_queue) do
      {{:value, {request, prompt, opts}}, new_queue} ->
        new_state = %{state | query_queue: new_queue}
        execute_request(request, prompt, opts, new_state)

      {:empty, _queue} ->
        state
    end
  end

  defp schedule_request_timeout(request_id) do
    Process.send_after(self(), {:request_timeout, request_id}, @request_timeout)
  end

  defp extract_lines(buffer) do
    lines = String.split(buffer, "\n")

    case List.pop_at(lines, -1) do
      {incomplete, complete_lines} ->
        {complete_lines, incomplete || ""}
    end
  end

  defp process_line("", state), do: state

  defp process_line(line, state) do
    with {:ok, json} <- Jason.decode(line),
         {:ok, message} <- Message.parse(json) do
      handle_message(message, state)
    else
      {:error, _} ->
        Logger.debug("Failed to parse line: #{line}")
        state
    end
  end

  defp handle_message(message, state) do
    # Extract session ID if present
    new_session_id = extract_session_id(message) || state.session_id

    # Process tool callback
    {new_pending_tools, _events} =
      ToolCallback.process_message(message, state.pending_tool_uses, state.tool_callback)

    state = %{state | session_id: new_session_id, pending_tool_uses: new_pending_tools}

    # Find the active request and dispatch message
    case find_active_request(state.requests) do
      {req_ref, request} ->
        updated_request = dispatch_message(message, request)

        # Check if this completes the request
        if result_message?(message) do
          complete_request(req_ref, updated_request, state)
        else
          %{state | requests: Map.put(state.requests, req_ref, updated_request)}
        end

      nil ->
        # No active request - might be a system message during init
        state
    end
  end

  defp dispatch_message(message, request) do
    case request.type do
      :sync ->
        # Store message for sync collection
        %{request | messages: request.messages ++ [message]}

      :stream ->
        # For stream requests, either deliver to waiting subscriber or queue
        case request.subscribers do
          [subscriber | rest] ->
            GenServer.reply(subscriber, {:message, message})
            %{request | subscribers: rest}

          [] ->
            %{request | messages: request.messages ++ [message]}
        end
    end
  end

  defp complete_request(req_ref, request, state) do
    case request.type do
      :sync ->
        result = extract_result(request.messages)
        GenServer.reply(request.from, result)

      :stream ->
        # Notify any waiting subscribers that we're done
        Enum.each(request.subscribers, fn subscriber ->
          GenServer.reply(subscriber, :done)
        end)
    end

    # Remove the completed request and process next queued request
    # Note: For stream requests, we keep them until explicitly cleaned up
    # so that receive_messages can still retrieve buffered messages
    new_requests =
      case request.type do
        :stream ->
          # Mark as completed but keep in map for message retrieval
          Map.put(state.requests, req_ref, %{request | status: :completed})

        _ ->
          # Remove sync/async requests immediately
          Map.delete(state.requests, req_ref)
      end

    new_state = %{state | requests: new_requests}
    process_next_in_queue(new_state)
  end

  defp extract_result(messages) do
    case Enum.find(messages, &match?(%Message.Result{}, &1)) do
      %Message.Result{is_error: true, result: error} ->
        {:error, {:claude_error, error}}

      %Message.Result{is_error: false, result: result} ->
        {:ok, result}

      nil ->
        {:error, :no_result}
    end
  end

  defp notify_error(request, error) do
    case request.type do
      :sync ->
        GenServer.reply(request.from, {:error, error})

      :stream ->
        Enum.each(request.subscribers, fn subscriber ->
          GenServer.reply(subscriber, {:error, error})
        end)
    end
  end

  defp find_active_request(requests) do
    Enum.find(requests, fn {_ref, req} -> req.status == :active end)
  end

  defp result_message?(%Message.Result{}), do: true
  defp result_message?(_), do: false

  defp extract_session_id(%Message.System{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(%Message.Assistant{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(%Message.Result{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(_), do: nil

  defp spawn_cli(state) do
    streaming_opts = Keyword.put(state.session_options, :input_format, :stream_json)

    case CLI.build_command("", state.api_key, streaming_opts, state.session_id) do
      {:ok, {executable, args}} ->
        # Remove empty prompt that build_command adds as last argument
        args_without_prompt = List.delete_at(args, -1)
        open_cli_port(executable, args_without_prompt, state, streaming_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp open_cli_port(executable, args, state, opts) do
    shell_path = :os.find_executable(~c"sh") || raise "sh not found"

    cmd_string = build_shell_command(executable, args, state, opts)
    # Don't redirect stdin - we need to write to it
    full_command = "(#{cmd_string}\n)"

    port =
      Port.open({:spawn_executable, shell_path}, [
        {:args, ["-c", full_command]},
        :binary,
        :exit_status,
        :stderr_to_stdout
      ])

    {:ok, port}
  rescue
    e -> {:error, {:port_open_failed, e}}
  end

  defp build_shell_command(executable, args, state, opts) do
    env_vars = prepare_env(state)

    env_prefix =
      Enum.map_join(env_vars, " ", fn {key, value} ->
        "#{key}=#{shell_escape(to_string(value))}"
      end)

    cwd_prefix =
      case Keyword.get(opts, :cwd) do
        nil -> ""
        cwd_path -> "cd #{shell_escape(cwd_path)} && "
      end

    cmd_string = Enum.map_join([executable | args], " ", &shell_escape/1)

    "#{cwd_prefix}#{env_prefix} #{cmd_string}"
  end

  defp prepare_env(state) do
    System.get_env()
    |> Map.take(["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"])
    |> maybe_put_api_override(state)
    |> Map.to_list()
    |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end

  defp maybe_put_api_override(env, %{api_key: api_key}) when is_binary(api_key) do
    Map.put(env, "ANTHROPIC_API_KEY", api_key)
  end

  defp maybe_put_api_override(env, _state), do: env

  defp shell_escape(str) when is_binary(str) do
    # Always quote empty strings or strings with special characters
    if str == "" or String.contains?(str, ["'", " ", "\"", "$", "`", "\\", "\n"]) do
      "'" <> String.replace(str, "'", "'\\''") <> "'"
    else
      str
    end
  end

  defp shell_escape(str), do: shell_escape(to_string(str))
end
