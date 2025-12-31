defmodule ClaudeCode.Session do
  @moduledoc """
  GenServer that manages Claude Code CLI subprocesses.

  Each session can handle multiple concurrent queries, with each query
  spawning its own CLI subprocess. Communication is via JSON streaming
  over stdout/stderr.
  """

  use GenServer

  alias ClaudeCode.CLI
  alias ClaudeCode.Message
  alias ClaudeCode.Message.StreamEvent
  alias ClaudeCode.Options
  alias ClaudeCode.ToolCallback

  require Logger

  defstruct [
    :api_key,
    :model,
    :active_requests,
    :session_options,
    :session_id,
    :tool_callback,
    :pending_tool_uses,
    # Streaming mode fields (for bidirectional I/O with --input-format stream-json)
    :streaming_port,
    :streaming_session_id,
    :streaming_requests,
    :streaming_buffer
  ]

  @request_timeout 300_000

  # Request tracking structure
  defmodule RequestInfo do
    @moduledoc false
    defstruct [
      :id,
      # :sync | :stream
      :type,
      :port,
      :buffer,
      # For sync requests
      :from,
      # For stream requests
      :subscribers,
      :messages,
      # :active | :completed
      :status,
      :created_at
    ]
  end

  # Client API

  @doc """
  Starts a new session GenServer.
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
    # Options are already validated in start_link/1
    state = %__MODULE__{
      api_key: Keyword.get(validated_opts, :api_key),
      model: Keyword.get(validated_opts, :model),
      session_options: validated_opts,
      active_requests: %{},
      session_id: nil,
      tool_callback: Keyword.get(validated_opts, :tool_callback),
      pending_tool_uses: %{},
      # Streaming mode - initialized to nil/empty until connect/1 is called
      streaming_port: nil,
      streaming_session_id: nil,
      streaming_requests: %{},
      streaming_buffer: ""
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:query, prompt, opts}, from, state) do
    request_id = make_ref()

    # Start a new CLI subprocess for this query
    case start_cli_process(prompt, state, opts) do
      {:ok, port} ->
        # Create request info
        request = %RequestInfo{
          id: request_id,
          type: :sync,
          port: port,
          buffer: "",
          from: from,
          messages: [],
          status: :active,
          created_at: System.monotonic_time()
        }

        # Register the request
        new_state = register_request(request, state)

        # Schedule timeout cleanup
        schedule_request_timeout(request_id)

        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query_stream, prompt, opts}, _from, state) do
    # Return immediately with a request ref, start CLI async
    request_ref = make_ref()

    # Schedule the CLI start as a cast to avoid blocking
    GenServer.cast(self(), {:start_stream_cli, request_ref, prompt, opts})

    {:reply, {:ok, request_ref}, state}
  end

  def handle_call({:query_async, prompt, opts}, {pid, _tag}, state) do
    # Return immediately with a request ref, start CLI async
    request_ref = make_ref()

    # Schedule the CLI start as a cast to avoid blocking
    GenServer.cast(self(), {:start_async_cli, request_ref, prompt, opts, pid})

    {:reply, {:ok, request_ref}, state}
  end

  def handle_call(:get_session_id, _from, state) do
    {:reply, {:ok, state.session_id}, state}
  end

  def handle_call(:clear_session, _from, state) do
    {:reply, :ok, %{state | session_id: nil}}
  end

  # Streaming Mode handle_call clauses

  def handle_call({:connect, opts}, _from, state) do
    if state.streaming_port do
      {:reply, {:error, :already_connected}, state}
    else
      case start_streaming_cli_process(state, opts) do
        {:ok, port} ->
          new_state = %{
            state
            | streaming_port: port,
              streaming_session_id: Keyword.get(opts, :resume, "default"),
              streaming_requests: %{},
              streaming_buffer: ""
          }

          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:stream_query, prompt}, _from, state) do
    if is_nil(state.streaming_port) do
      {:reply, {:error, :not_connected}, state}
    else
      # Build and send the message
      message = ClaudeCode.Input.user_message(prompt, state.streaming_session_id)
      Port.command(state.streaming_port, message <> "\n")

      # Create request ref and track it
      req_ref = make_ref()

      new_requests =
        Map.put(state.streaming_requests, req_ref, %{
          messages: [],
          subscribers: [],
          status: :active
        })

      new_state = %{state | streaming_requests: new_requests}
      {:reply, {:ok, req_ref}, new_state}
    end
  end

  def handle_call({:receive_next, req_ref}, from, state) do
    case Map.get(state.streaming_requests, req_ref) do
      nil ->
        {:reply, {:error, :unknown_request}, state}

      %{messages: [msg | rest]} = request ->
        # Return first message from queue
        updated_request = %{request | messages: rest}
        new_requests = Map.put(state.streaming_requests, req_ref, updated_request)
        {:reply, {:message, msg}, %{state | streaming_requests: new_requests}}

      %{status: :completed, messages: []} ->
        # No more messages and request is done
        new_requests = Map.delete(state.streaming_requests, req_ref)
        {:reply, :done, %{state | streaming_requests: new_requests}}

      %{status: :active, messages: []} = request ->
        # No messages yet, subscribe for next one
        updated_request = %{request | subscribers: [from | request.subscribers]}
        new_requests = Map.put(state.streaming_requests, req_ref, updated_request)
        {:noreply, %{state | streaming_requests: new_requests}}
    end
  end

  def handle_call({:interrupt, _req_ref}, _from, state) do
    if is_nil(state.streaming_port) do
      {:reply, {:error, :not_connected}, state}
    else
      # Send interrupt signal - this is platform-specific
      # On Unix, we can send SIGINT to the port
      Port.command(state.streaming_port, "\x03")
      {:reply, :ok, state}
    end
  end

  def handle_call(:disconnect, _from, state) do
    if is_nil(state.streaming_port) do
      {:reply, {:error, :not_connected}, state}
    else
      safe_close_port(state.streaming_port)

      new_state = %{
        state
        | streaming_port: nil,
          streaming_session_id: nil,
          streaming_requests: %{},
          streaming_buffer: ""
      }

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:stream_cleanup, request_ref}, state) do
    # Remove the request if it exists
    new_state = cleanup_request(request_ref, state)
    {:noreply, new_state}
  end

  def handle_cast({:start_stream_cli, request_ref, prompt, opts}, state) do
    # Start CLI process for streaming
    case start_cli_process(prompt, state, opts) do
      {:ok, port} ->
        request = %RequestInfo{
          id: request_ref,
          type: :stream,
          port: port,
          buffer: "",
          subscribers: [],
          messages: [],
          status: :active,
          created_at: System.monotonic_time()
        }

        new_state = register_request(request, state)
        schedule_request_timeout(request_ref)

        {:noreply, new_state}

      {:error, reason} ->
        # Notify error - no subscribers yet for pure streaming
        Logger.error("Failed to start CLI for stream request: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:start_async_cli, request_ref, prompt, opts, subscriber}, state) do
    # Start CLI process for async with subscriber
    case start_cli_process(prompt, state, opts) do
      {:ok, port} ->
        request = %RequestInfo{
          id: request_ref,
          type: :stream,
          port: port,
          buffer: "",
          subscribers: [subscriber],
          messages: [],
          status: :active,
          created_at: System.monotonic_time()
        }

        # Notify subscriber that streaming has started
        send(subscriber, {:claude_stream_started, request_ref})

        new_state = register_request(request, state)
        schedule_request_timeout(request_ref)

        {:noreply, new_state}

      {:error, reason} ->
        # Notify subscriber of error
        send(subscriber, {:claude_stream_error, request_ref, reason})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    # Check if this is the streaming port
    if port == state.streaming_port do
      # Handle streaming port data
      buffer = state.streaming_buffer <> data
      {lines, remaining_buffer} = extract_lines(buffer)

      new_state =
        Enum.reduce(lines, %{state | streaming_buffer: remaining_buffer}, fn line, acc_state ->
          process_streaming_line(line, acc_state)
        end)

      {:noreply, new_state}
    else
      # Otherwise, check active requests
      case find_request_by_port(port, state.active_requests) do
        {request_id, request} ->
          new_state = process_cli_output_for_request(data, request_id, request, state)
          {:noreply, new_state}

        nil ->
          Logger.warning("Received data from unknown port: #{inspect(port)}")
          {:noreply, state}
      end
    end
  end

  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    # Check if this is the streaming port
    if port == state.streaming_port do
      Logger.debug("Streaming CLI exited with status #{status}")

      # Mark all active streaming requests as completed
      new_requests =
        Map.new(state.streaming_requests, fn {ref, request} ->
          {ref, %{request | status: :completed}}
        end)

      # Notify all waiting subscribers
      for {_ref, %{subscribers: subscribers}} <- new_requests do
        for subscriber <- subscribers do
          GenServer.reply(subscriber, :done)
        end
      end

      new_state = %{
        state
        | streaming_port: nil,
          streaming_requests: new_requests
      }

      {:noreply, new_state}
    else
      # Otherwise, check active requests
      case find_request_by_port(port, state.active_requests) do
        {request_id, request} ->
          new_state = handle_request_exit(request_id, request, status, state)
          {:noreply, new_state}

        nil ->
          Logger.warning("Received exit status from unknown port: #{inspect(port)}")
          {:noreply, state}
      end
    end
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, state) when is_port(port) do
    # Find the request associated with this port
    case find_request_by_port(port, state.active_requests) do
      {request_id, request} ->
        Logger.error("Claude CLI port closed for request #{inspect(request_id)}: #{inspect(reason)}")
        new_state = handle_request_error(request_id, request, {:port_closed, reason}, state)
        {:noreply, new_state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({port, :eof}, state) when is_port(port) do
    # EOF received from port - this is expected when stdin is closed
    {:noreply, state}
  end

  def handle_info({:request_timeout, request_id}, state) do
    # Clean up request if it still exists
    case Map.get(state.active_requests, request_id) do
      nil ->
        {:noreply, state}

      request ->
        Logger.warning("Request #{inspect(request_id)} timed out after #{@request_timeout}ms")
        new_state = handle_request_error(request_id, request, :timeout, state)
        {:noreply, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Close all active ports
    for {_id, %{port: port}} <- state.active_requests do
      safe_close_port(port)
    end

    :ok
  end

  # Private Functions

  defp register_request(request, state) do
    %{state | active_requests: Map.put(state.active_requests, request.id, request)}
  end

  defp find_request_by_port(port, active_requests) do
    Enum.find(active_requests, fn {_id, request} -> request.port == port end)
  end

  defp schedule_request_timeout(request_id) do
    Process.send_after(self(), {:request_timeout, request_id}, @request_timeout)
  end

  defp process_cli_output_for_request(data, request_id, request, state) do
    # Append to request-specific buffer
    buffer = request.buffer <> data

    # Process complete lines
    {lines, remaining_buffer} = extract_lines(buffer)

    # Process each complete line for this request
    # Thread state through to handle tool callback updates
    {updated_request, should_complete, new_session_id, updated_state} =
      Enum.reduce(lines, {request, false, state.session_id, state}, fn line, {req, complete, session_id, st} ->
        case process_json_line_for_request(line, req, st) do
          {:ok, updated_req, :result, new_st} ->
            # Extract session ID from result message if available
            result_session_id = extract_session_id_from_request(updated_req)
            {updated_req, true, result_session_id || session_id, new_st}

          {:ok, updated_req, _message_type, new_st} ->
            # Extract session ID from any message type
            msg_session_id = extract_session_id_from_request(updated_req)
            {updated_req, complete, msg_session_id || session_id, new_st}

          {:error, _reason} ->
            # Skip invalid JSON lines
            {req, complete, session_id, st}
        end
      end)

    # Update buffer
    updated_request = %{updated_request | buffer: remaining_buffer}

    # Update state with new session ID and request
    new_state = %{
      updated_state
      | active_requests: Map.put(updated_state.active_requests, request_id, updated_request),
        session_id: new_session_id
    }

    # Complete request if we received a result message
    if should_complete do
      complete_request(request_id, updated_request, new_state)
    else
      new_state
    end
  end

  defp extract_lines(buffer) do
    lines = String.split(buffer, "\n")

    case List.pop_at(lines, -1) do
      {incomplete, complete_lines} ->
        {complete_lines, incomplete || ""}
    end
  end

  defp process_json_line_for_request("", _request, _state), do: {:error, :empty_line}

  defp process_json_line_for_request(line, request, state) do
    case Jason.decode(line) do
      {:ok, json} ->
        case Message.parse(json) do
          {:ok, message} ->
            {updated_request, updated_state} = process_message_for_request(message, request, state)
            message_type = determine_message_type(message)
            {:ok, updated_request, message_type, updated_state}

          {:error, error} ->
            Logger.debug("Failed to parse message: #{inspect(error)}")
            {:error, error}
        end

      {:error, _reason} ->
        Logger.debug("Non-JSON output: #{line}")
        {:error, :invalid_json}
    end
  end

  defp determine_message_type(%Message.System{}), do: :system
  defp determine_message_type(%Message.Assistant{}), do: :assistant
  defp determine_message_type(%Message.User{}), do: :user
  defp determine_message_type(%Message.Result{}), do: :result
  defp determine_message_type(%StreamEvent{}), do: :stream_event

  defp process_message_for_request(message, request, state) do
    # Store message
    updated_request = %{request | messages: request.messages ++ [message]}

    # Process tool callback
    {new_pending_tools, _events} =
      ToolCallback.process_message(message, state.pending_tool_uses, state.tool_callback)

    updated_state = %{state | pending_tool_uses: new_pending_tools}

    # Send to subscribers if streaming
    case request.type do
      :stream ->
        Enum.each(request.subscribers, fn pid ->
          send(pid, {:claude_message, request.id, message})
        end)

      :sync ->
        # Just store for sync requests
        nil
    end

    {updated_request, updated_state}
  end

  defp complete_request(request_id, request, state) do
    # Extract result from messages
    result = extract_result_from_request(request)

    # Handle based on request type
    case request.type do
      :sync ->
        GenServer.reply(request.from, result)

      :stream ->
        # Notify subscribers that stream has ended
        Enum.each(request.subscribers, fn pid ->
          send(pid, {:claude_stream_end, request.id})
        end)
    end

    # Clean up
    cleanup_request(request_id, state)
  end

  defp extract_result_from_request(request) do
    # Find the result message
    case Enum.find(request.messages, &match?(%Message.Result{}, &1)) do
      %Message.Result{is_error: true, result: error} ->
        {:error, {:claude_error, error}}

      %Message.Result{is_error: false, result: result} ->
        {:ok, result}

      nil ->
        # No result message - this shouldn't happen
        {:error, :no_result}
    end
  end

  defp handle_request_exit(request_id, request, status, state) do
    if status == 0 do
      # Normal exit - wait for result message
      state
    else
      Logger.error("Claude CLI exited with status #{status} for request #{inspect(request_id)}")
      handle_request_error(request_id, request, {:cli_exit, status}, state)
    end
  end

  defp handle_request_error(request_id, request, error, state) do
    # Send error based on request type
    case request.type do
      :sync ->
        GenServer.reply(request.from, {:error, error})

      :stream ->
        # Notify subscribers of error
        Enum.each(request.subscribers, fn pid ->
          send(pid, {:claude_stream_error, request.id, error})
        end)
    end

    # Clean up
    cleanup_request(request_id, state)
  end

  defp cleanup_request(request_id, state) do
    case Map.get(state.active_requests, request_id) do
      nil ->
        state

      request ->
        # Close port if still open
        safe_close_port(request.port)

        # Remove from active requests
        %{state | active_requests: Map.delete(state.active_requests, request_id)}
    end
  end

  defp safe_close_port(port) do
    if Port.info(port) do
      Port.close(port)
    end
  catch
    :error, :badarg -> :ok
  end

  defp start_cli_process(prompt, state, query_opts) do
    with {:ok, validated_query_opts} <- Options.validate_query_options(query_opts),
         final_opts = Options.merge_options(state.session_options, validated_query_opts),
         {:ok, {executable, args}} <- CLI.build_command(prompt, state.api_key, final_opts, state.session_id) do
      open_cli_port(executable, args, state, final_opts, redirect_stdin: true)
    else
      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, {:invalid_query_options, error}}

      {:error, reason} ->
        {:error, reason}
    end
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
    if String.contains?(str, ["'", " ", "\"", "$", "`", "\\", "\n"]) do
      # Use single quotes and escape any single quotes
      "'" <> String.replace(str, "'", "'\\''") <> "'"
    else
      str
    end
  end

  defp shell_escape(str), do: shell_escape(to_string(str))

  defp extract_session_id_from_request(request) do
    # Get the last message from the request (the one we just processed)
    case List.last(request.messages) do
      %Message.System{session_id: session_id} when not is_nil(session_id) ->
        session_id

      %Message.Assistant{session_id: session_id} when not is_nil(session_id) ->
        session_id

      %Message.Result{session_id: session_id} when not is_nil(session_id) ->
        session_id

      _ ->
        nil
    end
  end

  # ==========================================================================
  # Streaming Mode API (V2-style bidirectional I/O)
  # ==========================================================================

  @doc """
  Connects the session in streaming mode for bidirectional communication.

  This spawns a long-running CLI subprocess with `--input-format stream-json`
  that accepts messages via stdin and returns responses via stdout.

  ## Options

    * `:resume` - Session ID to resume a previous conversation

  ## Examples

      :ok = ClaudeCode.Session.connect(session)

      # Resume a previous session
      :ok = ClaudeCode.Session.connect(session, resume: "session-123")

  """
  @spec connect(GenServer.server(), keyword()) :: :ok | {:error, term()}
  def connect(session, opts \\ []) do
    GenServer.call(session, {:connect, opts})
  end

  @doc """
  Sends a query to the connected streaming session.

  Returns a request reference that can be used with `receive_messages/2` or
  `receive_response/2` to get the response.

  ## Examples

      {:ok, req_ref} = ClaudeCode.Session.stream_query(session, "Hello!")

  """
  @spec stream_query(GenServer.server(), String.t()) :: {:ok, reference()} | {:error, term()}
  def stream_query(session, prompt) do
    GenServer.call(session, {:stream_query, prompt})
  end

  @doc """
  Returns a Stream of all messages for a streaming request.

  The stream yields messages as they arrive from the CLI.

  ## Examples

      session
      |> ClaudeCode.Session.receive_messages(req_ref)
      |> Stream.each(&IO.inspect/1)
      |> Stream.run()

  """
  @spec receive_messages(GenServer.server(), reference()) :: Enumerable.t()
  def receive_messages(session, req_ref) do
    Stream.resource(
      fn -> {:ok, session, req_ref} end,
      fn
        {:ok, session, req_ref} ->
          case GenServer.call(session, {:receive_next, req_ref}, :infinity) do
            {:message, message} ->
              {[message], {:ok, session, req_ref}}

            :done ->
              {:halt, :done}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        state ->
          {:halt, state}
      end,
      fn _state -> :ok end
    )
  end

  @doc """
  Returns a Stream of messages until a Result message is received.

  This is useful when you want to process all messages for a single turn
  and stop when Claude finishes responding.

  ## Examples

      session
      |> ClaudeCode.Session.receive_response(req_ref)
      |> Stream.filter(&match?(%Message.Assistant{}, &1))
      |> Enum.each(&process_response/1)

  """
  @spec receive_response(GenServer.server(), reference()) :: Enumerable.t()
  def receive_response(session, req_ref) do
    session
    |> receive_messages(req_ref)
    |> Stream.transform(:continue, fn
      %Message.Result{} = msg, :continue ->
        {[msg], :done}

      msg, :continue ->
        {[msg], :continue}

      _msg, :done ->
        {:halt, :done}
    end)
  end

  @doc """
  Interrupts an in-progress streaming request.

  ## Examples

      :ok = ClaudeCode.Session.interrupt(session, req_ref)

  """
  @spec interrupt(GenServer.server(), reference()) :: :ok | {:error, term()}
  def interrupt(session, req_ref) do
    GenServer.call(session, {:interrupt, req_ref})
  end

  @doc """
  Disconnects the streaming session.

  This closes the CLI subprocess stdin and waits for it to exit.

  ## Examples

      :ok = ClaudeCode.Session.disconnect(session)

  """
  @spec disconnect(GenServer.server()) :: :ok | {:error, term()}
  def disconnect(session) do
    GenServer.call(session, :disconnect)
  end

  defp process_streaming_line("", state), do: state

  defp process_streaming_line(line, state) do
    with {:ok, json} <- Jason.decode(line),
         {:ok, message} <- Message.parse(json) do
      deliver_streaming_message(message, state)
    else
      {:error, _} ->
        Logger.debug("Failed to parse streaming line: #{line}")
        state
    end
  end

  defp deliver_streaming_message(message, state) do
    new_session_id = extract_session_id(message) || state.streaming_session_id

    case find_active_streaming_request(state.streaming_requests) do
      {req_ref, request} ->
        updated_request = dispatch_to_request(message, request)
        new_requests = Map.put(state.streaming_requests, req_ref, updated_request)
        %{state | streaming_requests: new_requests, streaming_session_id: new_session_id}

      nil ->
        %{state | streaming_session_id: new_session_id}
    end
  end

  defp dispatch_to_request(message, request) do
    case request.subscribers do
      [subscriber | rest] ->
        GenServer.reply(subscriber, {:message, message})
        request = %{request | subscribers: rest}
        mark_completed_if_result(request, message)

      [] ->
        request = %{request | messages: request.messages ++ [message]}
        mark_completed_if_result(request, message)
    end
  end

  defp mark_completed_if_result(request, %Message.Result{}) do
    %{request | status: :completed}
  end

  defp mark_completed_if_result(request, _message), do: request

  defp find_active_streaming_request(requests) do
    # Find the most recently added active request
    requests
    |> Enum.filter(fn {_ref, req} -> req.status == :active end)
    |> List.last()
  end

  defp extract_session_id(%Message.System{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(%Message.Assistant{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(%Message.Result{session_id: sid}) when not is_nil(sid), do: sid
  defp extract_session_id(_), do: nil

  defp start_streaming_cli_process(state, opts) do
    streaming_opts = Keyword.put(state.session_options, :input_format, :stream_json)
    resume_session_id = Keyword.get(opts, :resume)

    case CLI.build_command("", state.api_key, streaming_opts, resume_session_id) do
      {:ok, {executable, args}} ->
        # Remove empty prompt that build_command adds as last argument
        args_without_prompt = List.delete_at(args, -1)
        open_cli_port(executable, args_without_prompt, state, streaming_opts, redirect_stdin: false)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Common port opening logic for both one-shot and streaming modes
  defp open_cli_port(executable, args, state, opts, port_opts) do
    redirect_stdin = Keyword.get(port_opts, :redirect_stdin, true)

    try do
      shell_path = :os.find_executable(~c"sh") || raise "sh not found"

      cmd_string = build_shell_command(executable, args, state, opts)
      full_command = if redirect_stdin, do: "(#{cmd_string}\n) </dev/null", else: "(#{cmd_string}\n)"

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
end
