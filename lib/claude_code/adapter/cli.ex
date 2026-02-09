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

  alias ClaudeCode.Adapter
  alias ClaudeCode.CLI
  alias ClaudeCode.Message
  alias ClaudeCode.Message.ResultMessage

  require Logger

  @shell_special_chars ["'", " ", "\"", "$", "`", "\\", "\n", ";", "&", "|", "(", ")"]

  defstruct [
    :session,
    :session_options,
    :port,
    :buffer,
    :current_request,
    :api_key,
    status: :provisioning
  ]

  # ============================================================================
  # Client API (Adapter Behaviour)
  # ============================================================================

  @impl ClaudeCode.Adapter
  def start_link(session, opts) do
    GenServer.start_link(__MODULE__, {session, opts})
  end

  @impl ClaudeCode.Adapter
  def send_query(adapter, request_id, prompt, opts) do
    GenServer.call(adapter, {:query, request_id, prompt, opts}, :infinity)
  end

  @impl ClaudeCode.Adapter
  def interrupt(adapter) do
    GenServer.call(adapter, :interrupt)
  end

  @impl ClaudeCode.Adapter
  def health(adapter) do
    GenServer.call(adapter, :health)
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
      buffer: "",
      api_key: Keyword.get(opts, :api_key)
    }

    Process.link(session)
    Adapter.notify_status(session, :provisioning)

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    case spawn_cli(state) do
      {:ok, port} ->
        Adapter.notify_status(state.session, :ready)
        {:noreply, %{state | port: port, buffer: "", status: :ready}}

      {:error, reason} ->
        Adapter.notify_status(state.session, {:error, reason})
        {:noreply, %{state | status: :disconnected}}
    end
  end

  @impl GenServer
  def handle_call({:query, request_id, prompt, opts}, _from, state) do
    session_id = Keyword.get(opts, :session_id, "default")

    case ensure_connected(state) do
      {:ok, connected_state} ->
        message = ClaudeCode.Input.user_message(prompt, session_id)
        Port.command(connected_state.port, message <> "\n")
        {:reply, :ok, %{connected_state | current_request: request_id}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:interrupt, _from, %{port: port, current_request: request_id} = state)
      when not is_nil(port) and not is_nil(request_id) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        System.cmd("kill", ["-INT", to_string(os_pid)])
        Adapter.notify_done(state.session, request_id, :interrupted)
        {:reply, :ok, %{state | current_request: nil}}

      nil ->
        {:reply, {:error, :port_not_running}, state}
    end
  end

  def handle_call(:interrupt, _from, state) do
    {:reply, {:error, :no_active_request}, state}
  end

  @impl GenServer
  def handle_call(:health, _from, state) do
    health =
      case state do
        %{status: :provisioning} -> {:unhealthy, :provisioning}
        %{port: port} when not is_nil(port) -> if(Port.info(port), do: :healthy, else: {:unhealthy, :port_dead})
        _ -> {:unhealthy, :not_connected}
      end

    {:reply, health, state}
  end

  @impl GenServer
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {lines, remaining_buffer} = extract_lines(state.buffer <> data)

    new_state =
      Enum.reduce(lines, %{state | buffer: remaining_buffer}, fn line, acc_state ->
        process_line(line, acc_state)
      end)

    {:noreply, new_state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.debug("CLI exited with status #{status}")
    {:noreply, handle_port_disconnect(state, {:cli_exit, status})}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.error("CLI port closed: #{inspect(reason)}")
    {:noreply, handle_port_disconnect(state, {:port_closed, reason})}
  end

  def handle_info({port, :eof}, %{port: port} = state) do
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

  defp handle_port_disconnect(state, error) do
    if state.current_request do
      Adapter.notify_error(state.session, state.current_request, error)
    end

    %{state | port: nil, current_request: nil, buffer: "", status: :disconnected}
  end

  defp ensure_connected(%{status: :provisioning}), do: {:error, :provisioning}

  defp ensure_connected(%{port: nil, status: :disconnected} = state) do
    case spawn_cli(state) do
      {:ok, port} ->
        Adapter.notify_status(state.session, :ready)
        {:ok, %{state | port: port, buffer: "", status: :ready}}

      {:error, reason} ->
        Logger.error("Failed to reconnect to CLI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_connected(state), do: {:ok, state}

  defp spawn_cli(state) do
    streaming_opts = Keyword.put(state.session_options, :input_format, :stream_json)
    resume_session_id = Keyword.get(state.session_options, :resume)

    case CLI.build_command("", state.api_key, streaming_opts, resume_session_id) do
      {:ok, {executable, args}} ->
        open_cli_port(executable, List.delete_at(args, -1), state, streaming_opts)

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
    env_prefix =
      state
      |> prepare_env()
      |> Enum.map_join(" ", fn {key, value} ->
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
    state.session_options
    |> build_env(state.api_key)
    |> Map.to_list()
  end

  # ============================================================================
  # Testable Functions (public but not part of API)
  # ============================================================================

  @doc false
  def sdk_env_vars do
    %{
      "CLAUDE_CODE_ENTRYPOINT" => "sdk-ex",
      "CLAUDE_AGENT_SDK_VERSION" => ClaudeCode.version()
    }
  end

  @doc false
  def build_env(session_options, api_key) do
    user_env = Keyword.get(session_options, :env, %{})

    System.get_env()
    |> Map.merge(user_env)
    |> Map.merge(sdk_env_vars())
    |> maybe_put_api_key(api_key)
    |> maybe_put_file_checkpointing(session_options)
  end

  defp maybe_put_api_key(env, api_key) when is_binary(api_key) do
    Map.put(env, "ANTHROPIC_API_KEY", api_key)
  end

  defp maybe_put_api_key(env, _), do: env

  defp maybe_put_file_checkpointing(env, opts) do
    if Keyword.get(opts, :enable_file_checkpointing, false) do
      Map.put(env, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING", "true")
    else
      env
    end
  end

  @doc false
  # Semicolons must be escaped because they are command separators in shell.
  # This is critical for system env vars like LS_COLORS that contain semicolons.
  def shell_escape(str) when is_binary(str) do
    if str == "" or String.contains?(str, @shell_special_chars) do
      "'" <> String.replace(str, "'", "'\\''") <> "'"
    else
      str
    end
  end

  def shell_escape(str), do: shell_escape(to_string(str))

  @doc false
  def extract_lines(buffer) do
    case String.split(buffer, "\n") do
      [incomplete] -> {[], incomplete}
      lines -> {List.delete_at(lines, -1), List.last(lines)}
    end
  end

  # ============================================================================
  # Private Functions - Message Processing
  # ============================================================================

  defp process_line("", state), do: state

  defp process_line(line, %{current_request: nil} = state) do
    parse_line(line)
    state
  end

  defp process_line(line, state) do
    case parse_line(line) do
      {:ok, message} ->
        Adapter.notify_message(state.session, state.current_request, message)

        if match?(%ResultMessage{}, message) do
          Adapter.notify_done(state.session, state.current_request, :completed)
          %{state | current_request: nil}
        else
          state
        end

      {:error, _} ->
        state
    end
  end

  defp parse_line(line) do
    with {:ok, json} <- Jason.decode(line),
         {:ok, message} <- Message.parse(json) do
      {:ok, message}
    else
      {:error, reason} ->
        Logger.debug("Failed to parse line: #{line}")
        {:error, reason}
    end
  end
end
