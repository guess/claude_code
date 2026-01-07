defmodule ClaudeCode.Adapter.CLI do
  @moduledoc """
  CLI adapter that manages a persistent Port connection to the Claude CLI.

  This adapter:
  - Spawns the CLI subprocess with `--input-format stream-json`
  - Receives async messages from the Port
  - Parses JSON and forwards structured messages to Session
  - Handles Port lifecycle (connect, reconnect, cleanup)
  """

  @behaviour ClaudeCode.Adapter

  use GenServer

  alias ClaudeCode.CLI
  alias ClaudeCode.Message
  alias ClaudeCode.Message.ResultMessage

  require Logger

  defstruct [
    :session,
    :session_options,
    :port,
    :buffer,
    :current_request,
    :api_key
  ]

  # ============================================================================
  # Client API (Adapter Behaviour)
  # ============================================================================

  @impl ClaudeCode.Adapter
  def start_link(session, opts) do
    GenServer.start_link(__MODULE__, {session, opts})
  end

  @impl ClaudeCode.Adapter
  def send_query(adapter, request_id, prompt, session_id, opts) do
    GenServer.call(adapter, {:query, request_id, prompt, session_id, opts})
  end

  @impl ClaudeCode.Adapter
  def stop(adapter) do
    GenServer.stop(adapter, :normal)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl GenServer
  def init({session, opts}) do
    state = %__MODULE__{
      session: session,
      session_options: opts,
      port: nil,
      buffer: "",
      current_request: nil,
      api_key: Keyword.get(opts, :api_key)
    }

    # Link to session for lifecycle management
    Process.link(session)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:query, request_id, prompt, session_id, _opts}, _from, state) do
    case ensure_connected(state) do
      {:ok, connected_state} ->
        # Send query to CLI
        message = ClaudeCode.Input.user_message(prompt, session_id || "default")
        Port.command(connected_state.port, message <> "\n")

        new_state = %{connected_state | current_request: request_id}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
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

    if state.current_request do
      send(state.session, {:adapter_error, state.current_request, {:cli_exit, status}})
    end

    {:noreply, %{state | port: nil, current_request: nil, buffer: ""}}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.error("CLI port closed: #{inspect(reason)}")

    if state.current_request do
      send(state.session, {:adapter_error, state.current_request, {:port_closed, reason}})
    end

    {:noreply, %{state | port: nil, current_request: nil, buffer: ""}}
  end

  def handle_info({port, :eof}, %{port: port} = state) do
    # EOF received - this is expected when stdin is closed
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("CLI Adapter unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.port && Port.info(state.port) do
      Port.close(state.port)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  # ============================================================================
  # Private Functions - Port Management
  # ============================================================================

  defp ensure_connected(%{port: nil} = state) do
    case spawn_cli(state) do
      {:ok, port} ->
        {:ok, %{state | port: port, buffer: ""}}

      {:error, reason} ->
        Logger.error("Failed to connect to CLI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_connected(state), do: {:ok, state}

  defp spawn_cli(state) do
    streaming_opts = Keyword.put(state.session_options, :input_format, :stream_json)
    resume_session_id = Keyword.get(state.session_options, :resume)

    case CLI.build_command("", state.api_key, streaming_opts, resume_session_id) do
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

    port =
      Port.open({:spawn_executable, shell_path}, [
        {:args, ["-c", cmd_string]},
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

    "#{cwd_prefix}#{env_prefix}exec #{cmd_string}"
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

  # ============================================================================
  # Testable Functions (public but not part of API)
  # ============================================================================

  @doc false
  # Escapes a string for safe use in shell commands.
  # Uses single-quote escaping which handles most special characters.
  def shell_escape(str) when is_binary(str) do
    if str == "" or String.contains?(str, ["'", " ", "\"", "$", "`", "\\", "\n"]) do
      "'" <> String.replace(str, "'", "'\\''") <> "'"
    else
      str
    end
  end

  def shell_escape(str), do: shell_escape(to_string(str))

  @doc false
  # Extracts complete lines from a buffer, returning {complete_lines, remaining_buffer}.
  # Used for processing newline-delimited JSON from the CLI.
  def extract_lines(buffer) do
    lines = String.split(buffer, "\n")

    case List.pop_at(lines, -1) do
      {incomplete, complete_lines} ->
        {complete_lines, incomplete || ""}
    end
  end

  # ============================================================================
  # Private Functions - Message Processing
  # ============================================================================

  defp process_line("", state), do: state

  defp process_line(line, state) do
    with {:ok, json} <- Jason.decode(line),
         {:ok, message} <- Message.parse(json) do
      if state.current_request do
        # Send message to session
        send(state.session, {:adapter_message, state.current_request, message})

        # Check if this is the final message
        if result_message?(message) do
          send(state.session, {:adapter_done, state.current_request})
          %{state | current_request: nil}
        else
          state
        end
      else
        state
      end
    else
      {:error, _} ->
        Logger.debug("Failed to parse line: #{line}")
        state
    end
  end

  defp result_message?(%ResultMessage{}), do: true
  defp result_message?(_), do: false
end
