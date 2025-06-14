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

  @default_model "sonnet"

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
    # Process the raw binary data from the CLI subprocess
    new_state = process_cli_output(data, state)
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

  def handle_info({port, :eof}, state) when is_port(port) do
    # EOF received from port - this is expected when stdin is closed
    {:noreply, state}
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
    case Message.parse(json) do
      {:ok, message} ->
        case message do
          %Message.System{} ->
            handle_system_message(message, state)

          %Message.Assistant{} ->
            handle_assistant_message(message, state)

          %Message.User{} ->
            handle_user_message(message, state)

          %Message.Result{} ->
            handle_result_message(message, state)
        end

      {:error, error} ->
        Logger.error("Failed to parse message: #{inspect(error)}")
        state
    end
  end

  defp handle_system_message(message, state) do
    # System messages provide session initialization info
    Logger.info("Session initialized with model: #{message.model}, session_id: #{message.session_id}")
    state
  end

  defp handle_assistant_message(message, state) do
    # For now, just log assistant messages - the actual response comes in the result message
    Logger.debug("Received assistant message: #{inspect(message)}")
    state
  end

  defp handle_user_message(message, state) do
    # User messages contain tool results - just log for now
    Logger.debug("Received user message with tool results: #{inspect(message)}")
    state
  end

  defp handle_result_message(message, state) do
    # Get the first (and only for Phase 1) pending request
    case Map.keys(state.pending_requests) do
      [request_id | _] ->
        request = Map.get(state.pending_requests, request_id)

        # Reply based on whether it's an error or success
        reply =
          if message.is_error do
            {:error, {:claude_error, message.result}}
          else
            {:ok, message.result}
          end

        GenServer.reply(request.from, reply)

        # Remove the request
        %{state | pending_requests: Map.delete(state.pending_requests, request_id)}

      [] ->
        Logger.warning("Received result message with no pending requests")
        state
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
