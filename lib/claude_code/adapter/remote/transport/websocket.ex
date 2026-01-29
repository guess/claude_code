defmodule ClaudeCode.Adapter.Remote.Transport.WebSocket do
  @moduledoc """
  WebSocket transport implementation using WebSockex.

  This transport connects to a remote WebSocket endpoint that bridges to
  the Claude CLI's stdin/stdout. It handles frame parsing, buffering of
  incomplete JSON messages, and automatic reconnection.

  ## Message Flow

  1. SDK sends JSON messages via `send_input/2`
  2. Transport forwards to WebSocket server as text frames
  3. Server writes to CLI stdin
  4. CLI stdout is read by server and sent as text frames
  5. Transport buffers and forwards complete lines to subscriber

  ## Telemetry Events

  This transport emits the following telemetry events:

  - `[:claude_code, :remote, :connect, :start]` - Connection attempt started
  - `[:claude_code, :remote, :connect, :stop]` - Connection established
  - `[:claude_code, :remote, :connect, :exception]` - Connection failed
  - `[:claude_code, :remote, :reconnect, :start]` - Reconnection attempt started
  - `[:claude_code, :remote, :reconnect, :stop]` - Reconnection successful
  """

  @behaviour ClaudeCode.Adapter.Remote.Transport

  use WebSockex

  alias ClaudeCode.Adapter.Remote.Transport

  require Logger

  defstruct [:subscriber, :endpoint, :buffer, :reconnect_attempts, :max_reconnect_attempts]

  # ============================================================================
  # Transport Behaviour Implementation
  # ============================================================================

  @impl Transport
  def connect(endpoint, opts) do
    subscriber = Keyword.fetch!(opts, :subscriber)
    max_reconnect_attempts = Keyword.get(opts, :reconnect_attempts, 3)

    state = %__MODULE__{
      subscriber: subscriber,
      endpoint: endpoint,
      buffer: "",
      reconnect_attempts: 0,
      max_reconnect_attempts: max_reconnect_attempts
    }

    start_time = System.monotonic_time()
    emit_connect_start(endpoint)

    websocket_opts = [
      # WebSockex options
      handle_initial_conn_failure: true,
      async: true
    ]

    case WebSockex.start_link(endpoint, __MODULE__, state, websocket_opts) do
      {:ok, pid} ->
        emit_connect_stop(endpoint, start_time)
        {:ok, pid}

      {:error, reason} ->
        emit_connect_exception(endpoint, reason)
        {:error, reason}
    end
  end

  @impl Transport
  def send_input(transport, data) do
    WebSockex.send_frame(transport, {:text, data})
  end

  @impl Transport
  def disconnect(transport) do
    WebSockex.cast(transport, :disconnect)
  end

  @impl Transport
  def alive?(transport) do
    Process.alive?(transport)
  end

  # ============================================================================
  # WebSockex Callbacks
  # ============================================================================

  @impl WebSockex
  def handle_connect(_conn, state) do
    send(state.subscriber, {:transport_connected, state.endpoint})
    {:ok, %{state | reconnect_attempts: 0}}
  end

  @impl WebSockex
  def handle_frame({:text, data}, state) do
    # Buffer incoming data and extract complete lines
    buffer = state.buffer <> data
    {lines, remaining_buffer} = extract_lines(buffer)

    # Forward complete lines to subscriber
    for line <- lines, line != "" do
      send(state.subscriber, {:transport_data, line})
    end

    {:ok, %{state | buffer: remaining_buffer}}
  end

  def handle_frame({:binary, data}, state) do
    # Treat binary frames as text
    handle_frame({:text, data}, state)
  end

  def handle_frame({:ping, _}, state) do
    {:reply, {:pong, ""}, state}
  end

  def handle_frame({:pong, _}, state) do
    {:ok, state}
  end

  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast(:disconnect, state) do
    {:close, state}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.debug("WebSocket disconnected: #{inspect(reason)}")

    if state.reconnect_attempts < state.max_reconnect_attempts do
      emit_reconnect_start(state.reconnect_attempts + 1, state.endpoint)

      # WebSockex handles exponential backoff by default
      {:reconnect, %{state | reconnect_attempts: state.reconnect_attempts + 1}}
    else
      send(state.subscriber, {:transport_disconnected, {:reconnect_failed, state.reconnect_attempts}})
      {:ok, state}
    end
  end

  @impl WebSockex
  def terminate(reason, state) do
    Logger.debug("WebSocket transport terminating: #{inspect(reason)}")
    send(state.subscriber, {:transport_error, {:terminated, reason}})
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

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

  defp emit_connect_start(endpoint) do
    :telemetry.execute(
      [:claude_code, :remote, :connect, :start],
      %{system_time: System.system_time()},
      %{endpoint: endpoint}
    )
  end

  defp emit_connect_stop(endpoint, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:claude_code, :remote, :connect, :stop],
      %{duration: duration},
      %{endpoint: endpoint}
    )
  end

  defp emit_connect_exception(endpoint, reason) do
    :telemetry.execute(
      [:claude_code, :remote, :connect, :exception],
      %{system_time: System.system_time()},
      %{endpoint: endpoint, reason: reason}
    )
  end

  defp emit_reconnect_start(attempt, endpoint) do
    :telemetry.execute(
      [:claude_code, :remote, :reconnect, :start],
      %{system_time: System.system_time()},
      %{attempt: attempt, endpoint: endpoint}
    )
  end
end
