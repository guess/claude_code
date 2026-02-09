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
      port: nil,
      buffer: "",
      current_request: nil,
      api_key: Keyword.get(opts, :api_key),
      status: :provisioning
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
    session_id = Keyword.get(opts, :session_id)

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
  def handle_call(:health, _from, %{status: :provisioning} = state) do
    {:reply, {:unhealthy, :provisioning}, state}
  end

  def handle_call(:health, _from, %{port: port} = state) when not is_nil(port) do
    health =
      if Port.info(port) do
        :healthy
      else
        {:unhealthy, :port_dead}
      end

    {:reply, health, state}
  end

  def handle_call(:health, _from, state) do
    {:reply, {:unhealthy, :not_connected}, state}
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
      Adapter.notify_error(state.session, state.current_request, {:cli_exit, status})
    end

    {:noreply, %{state | port: nil, current_request: nil, buffer: "", status: :disconnected}}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.error("CLI port closed: #{inspect(reason)}")

    if state.current_request do
      Adapter.notify_error(state.session, state.current_request, {:port_closed, reason})
    end

    {:noreply, %{state | port: nil, current_request: nil, buffer: "", status: :disconnected}}
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

  defp ensure_connected(%{status: :provisioning} = _state) do
    {:error, :provisioning}
  end

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
    # Merge precedence (lowest to highest):
    # 1. All system environment variables (base)
    # 2. User-provided :env option (overrides)
    # 3. SDK-required variables (always set)
    # 4. API key override (if provided via :api_key option)
    state.session_options
    |> build_env(state.api_key)
    |> Map.to_list()
    |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end

  # ============================================================================
  # Testable Functions (public but not part of API)
  # ============================================================================

  @doc false
  # Returns the SDK-required environment variables that are always set.
  def sdk_env_vars do
    %{
      "CLAUDE_CODE_ENTRYPOINT" => "sdk-ex",
      "CLAUDE_AGENT_SDK_VERSION" => ClaudeCode.version()
    }
  end

  @doc false
  # Prepares the environment for the CLI subprocess with proper merge order.
  # Exposed for testing - see prepare_env/1 for the private implementation.
  def build_env(session_options, api_key) do
    user_env = Keyword.get(session_options, :env, %{})

    System.get_env()
    |> Map.merge(user_env)
    |> Map.merge(sdk_env_vars())
    |> maybe_put_api_override_map(api_key)
    |> maybe_put_file_checkpointing(session_options)
  end

  defp maybe_put_api_override_map(env, api_key) when is_binary(api_key) do
    Map.put(env, "ANTHROPIC_API_KEY", api_key)
  end

  defp maybe_put_api_override_map(env, _), do: env

  defp maybe_put_file_checkpointing(env, opts) do
    if Keyword.get(opts, :enable_file_checkpointing, false) do
      Map.put(env, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING", "true")
    else
      env
    end
  end

  @doc false
  # Escapes a string for safe use in shell commands.
  # Uses single-quote escaping which handles most special characters.
  # NOTE: `;` must be escaped because it's a command separator in shell.
  # This is critical when passing through system env vars like LS_COLORS.
  def shell_escape(str) when is_binary(str) do
    if str == "" or String.contains?(str, ["'", " ", "\"", "$", "`", "\\", "\n", ";", "&", "|", "(", ")"]) do
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
        Adapter.notify_message(state.session, state.current_request, message)

        # Check if this is the final message
        if result_message?(message) do
          Adapter.notify_done(state.session, state.current_request, :completed)
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
