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

  require Logger

  defstruct [:api_key, :model, :active_requests]

  @default_model "sonnet"
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
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      _ -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, @default_model)

    state = %__MODULE__{
      api_key: api_key,
      model: model,
      active_requests: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:query_sync, prompt, opts}, from, state) do
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
    # Find the request associated with this port
    case find_request_by_port(port, state.active_requests) do
      {request_id, request} ->
        # Process data for this specific request
        new_state = process_cli_output_for_request(data, request_id, request, state)
        {:noreply, new_state}

      nil ->
        Logger.warning("Received data from unknown port: #{inspect(port)}")
        {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    # Find the request associated with this port
    case find_request_by_port(port, state.active_requests) do
      {request_id, request} ->
        # Handle exit for this specific request
        new_state = handle_request_exit(request_id, request, status, state)
        {:noreply, new_state}

      nil ->
        Logger.warning("Received exit status from unknown port: #{inspect(port)}")
        {:noreply, state}
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
    {updated_request, should_complete} =
      Enum.reduce(lines, {request, false}, fn line, {req, complete} ->
        case process_json_line_for_request(line, req) do
          {:ok, updated_req, :result} ->
            {updated_req, true}

          {:ok, updated_req, _message_type} ->
            {updated_req, complete}

          {:error, _reason} ->
            # Skip invalid JSON lines
            {req, complete}
        end
      end)

    # Update buffer
    updated_request = %{updated_request | buffer: remaining_buffer}

    # Update state
    new_state = %{state | active_requests: Map.put(state.active_requests, request_id, updated_request)}

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

  defp process_json_line_for_request("", _request), do: {:error, :empty_line}

  defp process_json_line_for_request(line, request) do
    case Jason.decode(line) do
      {:ok, json} ->
        case Message.parse(json) do
          {:ok, message} ->
            updated_request = process_message_for_request(message, request)
            message_type = determine_message_type(message)
            {:ok, updated_request, message_type}

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

  defp process_message_for_request(message, request) do
    # Store message
    updated_request = %{request | messages: request.messages ++ [message]}

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

    updated_request
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

  defp start_cli_process(prompt, state, opts) do
    # Build the command
    case CLI.build_command(prompt, state.api_key, state.model, opts) do
      {:ok, {executable, args}} ->
        # Start the CLI subprocess
        # Environment variables need to be in the format [{key, value}] where both are charlists
        env_vars = [
          {~c"ANTHROPIC_API_KEY", String.to_charlist(state.api_key)}
        ]

        try do
          # Use the exact same approach as System.shell
          shell_path = :os.find_executable(~c"sh") || raise "sh not found"

          # Build the command string with proper escaping
          cmd_parts = [executable | args]
          cmd_string = Enum.map_join(cmd_parts, " ", &shell_escape/1)

          # Add environment variables to the command
          env_prefix =
            Enum.map_join(env_vars, " ", fn {key, value} ->
              "#{key}=#{shell_escape(to_string(value))}"
            end)

          # Build the full command exactly like System.shell does
          # Wrap in parentheses, add newline, and redirect stdin from /dev/null
          full_command = "(#{env_prefix} #{cmd_string}\n) </dev/null"

          port_opts = [
            {:args, ["-c", full_command]},
            :binary,
            :exit_status,
            :stderr_to_stdout
          ]

          port = Port.open({:spawn_executable, shell_path}, port_opts)
          {:ok, port}
        rescue
          e ->
            {:error, {:port_open_failed, e}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp shell_escape(str) when is_binary(str) do
    if String.contains?(str, ["'", " ", "\"", "$", "`", "\\", "\n"]) do
      # Use single quotes and escape any single quotes
      "'" <> String.replace(str, "'", "'\\''") <> "'"
    else
      str
    end
  end

  defp shell_escape(str), do: shell_escape(to_string(str))
end
