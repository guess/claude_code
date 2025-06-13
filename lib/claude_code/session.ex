defmodule ClaudeCode.Session do
  @moduledoc """
  GenServer that manages a Claude Code CLI subprocess.

  Each session maintains a single Claude CLI process and handles
  communication via JSON streaming over stdout/stderr.
  """

  use GenServer

  alias ClaudeCode.CLI
  alias ClaudeCode.Message

  require Logger

  defstruct [:port, :api_key, :model, :buffer, :pending_requests]

  @default_model "claude-3-5-haiku-20241022"

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
      buffer: "",
      pending_requests: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:query_sync, prompt, opts}, from, state) do
    # Start a new CLI subprocess for this query
    case start_cli_process(prompt, state, opts) do
      {:ok, port} ->
        # Store the request details
        request_id = make_ref()

        new_state = %{
          state
          | port: port,
            pending_requests:
              Map.put(state.pending_requests, request_id, %{
                from: from,
                buffer: "",
                messages: []
              })
        }

        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Process the data from the CLI subprocess
    # When using {:line, N}, data comes as {:eol, line} or {:noeol, partial}
    new_state =
      case data do
        {:eol, line} ->
          # Complete line received
          process_complete_line(line, state)

        {:noeol, partial} ->
          # Partial line, add to buffer
          %{state | buffer: state.buffer <> partial}

        binary when is_binary(binary) ->
          # Raw binary data (shouldn't happen with :line mode)
          process_cli_output(binary, state)
      end

    {:noreply, new_state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    # CLI process exited
    if status != 0 do
      Logger.error("Claude CLI exited with status #{status}")

      # Reply to all pending requests with an error
      for {_id, %{from: from}} <- state.pending_requests do
        GenServer.reply(from, {:error, {:cli_exit, status}})
      end
    end

    new_state = %{state | port: nil, pending_requests: %{}}
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.error("Claude CLI port closed: #{inspect(reason)}")

    # Reply to all pending requests with an error
    for {_id, %{from: from}} <- state.pending_requests do
      GenServer.reply(from, {:error, {:port_closed, reason}})
    end

    new_state = %{state | port: nil, pending_requests: %{}}
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{port: port} = _state) when not is_nil(port) do
    Port.close(port)
  end

  def terminate(_reason, _state), do: :ok

  # Private Functions

  defp start_cli_process(prompt, state, opts) do
    # Build the command
    case CLI.build_command(prompt, state.api_key, state.model, opts) do
      {:ok, {executable, args}} ->
        # Start the CLI subprocess
        # Environment variables need to be in the format [{key, value}] where both are charlists
        env_vars = [
          {~c"ANTHROPIC_API_KEY", String.to_charlist(state.api_key)}
        ]

        port_opts = [
          :binary,
          :exit_status,
          {:line, 65_536},
          {:args, args},
          {:env, env_vars}
        ]

        try do
          port = Port.open({:spawn_executable, executable}, port_opts)
          {:ok, port}
        rescue
          e ->
            {:error, {:port_open_failed, e}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_complete_line(line, state) when is_binary(line) do
    # Process a complete line of JSON
    process_json_line(line, state)
  end

  defp process_cli_output(data, state) do
    # Add data to buffer
    buffer = state.buffer <> data

    # Process complete lines
    {lines, remaining_buffer} = extract_lines(buffer)

    # Process each complete line
    new_state =
      Enum.reduce(lines, state, fn line, acc_state ->
        process_json_line(line, acc_state)
      end)

    %{new_state | buffer: remaining_buffer}
  end

  defp extract_lines(buffer) do
    lines = String.split(buffer, "\n")

    case List.pop_at(lines, -1) do
      {incomplete, complete_lines} ->
        {complete_lines, incomplete || ""}
    end
  end

  defp process_json_line("", state), do: state

  defp process_json_line(line, state) do
    case Jason.decode(line) do
      {:ok, json} ->
        process_message(json, state)

      {:error, _reason} ->
        # Skip non-JSON lines (might be debug output)
        Logger.debug("Non-JSON output: #{line}")
        state
    end
  end

  defp process_message(json, state) when is_map(json) do
    message = Message.from_json(json)

    case message.type do
      :assistant ->
        handle_assistant_message(message, state)

      :error ->
        handle_error_message(message, state)

      _other ->
        # For Phase 1, we'll just log other message types
        Logger.debug("Received message: #{inspect(message)}")
        state
    end
  end

  defp handle_assistant_message(message, state) do
    # Get the first (and only for Phase 1) pending request
    case Map.keys(state.pending_requests) do
      [request_id | _] ->
        request = Map.get(state.pending_requests, request_id)

        # Reply with the content
        GenServer.reply(request.from, {:ok, message.content})

        # Remove the request
        %{state | pending_requests: Map.delete(state.pending_requests, request_id)}

      [] ->
        Logger.warning("Received assistant message with no pending requests")
        state
    end
  end

  defp handle_error_message(message, state) do
    # Handle error messages
    case Map.keys(state.pending_requests) do
      [request_id | _] ->
        request = Map.get(state.pending_requests, request_id)

        # Reply with the error
        GenServer.reply(request.from, {:error, {:claude_error, message.content}})

        # Remove the request
        %{state | pending_requests: Map.delete(state.pending_requests, request_id)}

      [] ->
        Logger.warning("Received error with no pending requests: #{message.content}")
        state
    end
  end
end
