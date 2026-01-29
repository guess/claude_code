defmodule ClaudeCode.Adapter.Remote do
  @moduledoc """
  Remote adapter that executes Claude CLI on remote containers.

  This adapter connects to a remote container (Modal, E2B, Fly.io, or custom)
  via WebSocket and communicates with the Claude CLI running there. From the
  SDK's perspective, it behaves identically to the local CLI adapter.

  ## Architecture

  ```
  ┌─────────────────┐     WebSocket      ┌─────────────────────────────────┐
  │   Elixir SDK    │◄──────────────────►│     Remote Container            │
  │                 │                    │  ┌───────────────────────────┐  │
  │  Remote Adapter │                    │  │   Transport Server        │  │
  │                 │                    │  │  (WebSocket → stdin/out)  │  │
  └─────────────────┘                    │  └───────────────────────────┘  │
                                         │           ▲     │               │
                                         │           │     ▼               │
                                         │  ┌───────────────────────────┐  │
                                         │  │      Claude CLI           │  │
                                         │  │  (claude --stream-json)   │  │
                                         │  └───────────────────────────┘  │
                                         └─────────────────────────────────┘
  ```

  ## Usage

  ```elixir
  # With a custom endpoint (user manages container)
  {:ok, session} = ClaudeCode.start_link(
    adapter: {ClaudeCode.Adapter.Remote, [
      endpoint: "wss://my-container.example.com:8080"
    ]},
    api_key: System.get_env("ANTHROPIC_API_KEY")
  )

  # Works exactly like local execution
  result = ClaudeCode.query(session, "Hello from remote!")
  ```

  ## Options

  - `:endpoint` (required) - WebSocket endpoint URL
  - `:transport` - Transport module (default: `Transport.WebSocket`)
  - `:backend` - Backend module (default: `Backend.Custom`)
  - `:connect_timeout` - Connection timeout in ms (default: 30_000)
  - `:request_timeout` - Request timeout in ms (default: 300_000)
  - `:reconnect_attempts` - Max reconnection attempts (default: 3)
  - `:reconnect_interval` - Base interval between reconnects in ms (default: 1_000)
  - `:credential_mode` - How API keys are passed: `:inject` or `:proxy` (default: `:inject`)

  ## Telemetry Events

  The adapter emits the following telemetry events:

  - `[:claude_code, :remote, :connect, :start]` - Connection attempt started
  - `[:claude_code, :remote, :connect, :stop]` - Connection established
  - `[:claude_code, :remote, :connect, :exception]` - Connection failed
  - `[:claude_code, :remote, :reconnect, :start]` - Reconnection attempt started
  - `[:claude_code, :remote, :reconnect, :stop]` - Reconnection successful
  - `[:claude_code, :remote, :request, :start]` - Request started
  - `[:claude_code, :remote, :request, :stop]` - Request completed
  - `[:claude_code, :remote, :request, :exception]` - Request failed

  ## Error Handling

  Remote errors map to adapter protocol messages:

  | Remote Error | Adapter Message |
  |--------------|-----------------|
  | Connection failed | `{:adapter_error, request_id, {:connection_failed, reason}}` |
  | Connection lost mid-stream | `{:adapter_error, request_id, {:connection_lost, reason}}` |
  | Request timeout | `{:adapter_error, request_id, {:timeout, :request}}` |
  | Reconnect exhausted | `{:adapter_error, request_id, {:reconnect_failed, attempts}}` |
  """

  @behaviour ClaudeCode.Adapter

  use GenServer

  alias ClaudeCode.Adapter.Remote.Backend
  alias ClaudeCode.Adapter.Remote.Transport
  alias ClaudeCode.Message
  alias ClaudeCode.Message.ResultMessage

  require Logger

  defstruct [
    :session,
    :session_options,
    :transport,
    :transport_module,
    :backend_module,
    :endpoint,
    :api_key,
    :current_request,
    :buffer,
    :request_start_time,
    :opts
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
    # Extract remote-specific options
    remote_opts = Keyword.get(opts, :remote, [])
    endpoint = Keyword.get(remote_opts, :endpoint) || Keyword.get(opts, :endpoint)

    if !endpoint do
      raise ArgumentError, "Remote adapter requires :endpoint option"
    end

    transport_module =
      Keyword.get(remote_opts, :transport, Transport.WebSocket)

    backend_module =
      Keyword.get(remote_opts, :backend, Backend.Custom)

    state = %__MODULE__{
      session: session,
      session_options: opts,
      transport: nil,
      transport_module: transport_module,
      backend_module: backend_module,
      endpoint: endpoint,
      api_key: Keyword.get(opts, :api_key),
      current_request: nil,
      buffer: "",
      request_start_time: nil,
      opts: remote_opts
    }

    # Link to session for lifecycle management
    Process.link(session)

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:query, request_id, prompt, session_id, _opts}, _from, state) do
    case ensure_connected(state) do
      {:ok, connected_state} ->
        # Build and send the query message
        message = ClaudeCode.Input.user_message(prompt, session_id || "default")

        emit_request_start(request_id)

        case connected_state.transport_module.send_input(connected_state.transport, message <> "\n") do
          :ok ->
            new_state = %{
              connected_state
              | current_request: request_id,
                request_start_time: System.monotonic_time()
            }

            {:reply, :ok, new_state}

          {:error, reason} ->
            emit_request_exception(request_id, reason)
            {:reply, {:error, {:send_failed, reason}}, connected_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:transport_data, data}, state) do
    # Buffer incoming data and process complete JSON lines
    buffer = state.buffer <> data
    {lines, remaining_buffer} = extract_lines(buffer)

    new_state =
      Enum.reduce(lines, %{state | buffer: remaining_buffer}, fn line, acc_state ->
        process_line(line, acc_state)
      end)

    {:noreply, new_state}
  end

  def handle_info({:transport_connected, endpoint}, state) do
    Logger.debug("Remote transport connected to #{endpoint}")
    {:noreply, state}
  end

  def handle_info({:transport_disconnected, reason}, state) do
    Logger.warning("Remote transport disconnected: #{inspect(reason)}")

    if state.current_request do
      send(state.session, {:adapter_error, state.current_request, {:connection_lost, reason}})
    end

    {:noreply, %{state | transport: nil, current_request: nil, buffer: ""}}
  end

  def handle_info({:transport_error, reason}, state) do
    Logger.error("Remote transport error: #{inspect(reason)}")

    if state.current_request do
      emit_request_exception(state.current_request, reason)
      send(state.session, {:adapter_error, state.current_request, {:transport_error, reason}})
    end

    {:noreply, %{state | transport: nil, current_request: nil, buffer: ""}}
  end

  def handle_info(msg, state) do
    Logger.debug("Remote Adapter unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.transport && state.transport_module.alive?(state.transport) do
      state.transport_module.disconnect(state.transport)
    end

    :ok
  rescue
    _ -> :ok
  end

  # ============================================================================
  # Private Functions - Connection Management
  # ============================================================================

  defp ensure_connected(%{transport: nil} = state) do
    connect_timeout = Keyword.get(state.opts, :connect_timeout, 30_000)
    reconnect_attempts = Keyword.get(state.opts, :reconnect_attempts, 3)

    transport_opts = [
      subscriber: self(),
      connect_timeout: connect_timeout,
      reconnect_attempts: reconnect_attempts
    ]

    case state.transport_module.connect(state.endpoint, transport_opts) do
      {:ok, transport} ->
        {:ok, %{state | transport: transport, buffer: ""}}

      {:error, reason} ->
        Logger.error("Failed to connect to remote: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  defp ensure_connected(%{transport: transport} = state) do
    if state.transport_module.alive?(transport) do
      {:ok, state}
    else
      ensure_connected(%{state | transport: nil})
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
          emit_request_stop(state.current_request, state.request_start_time)
          send(state.session, {:adapter_done, state.current_request})
          %{state | current_request: nil, request_start_time: nil}
        else
          state
        end
      else
        state
      end
    else
      {:error, _} ->
        Logger.debug("Failed to parse line from remote: #{line}")
        state
    end
  end

  defp result_message?(%ResultMessage{}), do: true
  defp result_message?(_), do: false

  defp extract_lines(buffer) do
    lines = String.split(buffer, "\n")

    case List.pop_at(lines, -1) do
      {incomplete, complete_lines} ->
        {complete_lines, incomplete || ""}
    end
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp emit_request_start(request_id) do
    :telemetry.execute(
      [:claude_code, :remote, :request, :start],
      %{system_time: System.system_time()},
      %{request_id: request_id}
    )
  end

  defp emit_request_stop(request_id, start_time) when not is_nil(start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:claude_code, :remote, :request, :stop],
      %{duration: duration},
      %{request_id: request_id}
    )
  end

  defp emit_request_stop(_request_id, _start_time), do: :ok

  defp emit_request_exception(request_id, reason) do
    :telemetry.execute(
      [:claude_code, :remote, :request, :exception],
      %{system_time: System.system_time()},
      %{request_id: request_id, reason: reason}
    )
  end
end
