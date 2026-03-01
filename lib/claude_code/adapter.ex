defmodule ClaudeCode.Adapter do
  @moduledoc """
  Behaviour for ClaudeCode adapters.

  Adapters handle the full lifecycle of a Claude Code execution environment:
  provisioning, communication, health checking, and cleanup.

  ## Message Protocol

  Adapters communicate with Session by sending messages via the notification helpers.
  Session receives these as `handle_info` tuples:

  ### Transport notifications

  - `notify_message/3` → `{:adapter_message, request_id, struct | map | binary}` —
    A message struct, raw JSON map, or binary string. Structs are delivered
    directly; maps and binaries are parsed via `CLI.Parser`. Session
    auto-detects `ResultMessage` to complete the request.

  ### Lifecycle notifications

  - `notify_error/3` → `{:adapter_error, request_id, reason}` —
    An error occurred during the request (connection lost, CLI crash, etc.).

  - `notify_status/2` → `{:adapter_status, status}` —
    Adapter status change. Statuses: `:provisioning`, `:ready`, `{:error, reason}`.

  - `notify_control_request/3` → `{:adapter_control_request, request_id, request}` —
    Forwards a control protocol request (e.g. `can_use_tool`) from the CLI to Session.

  ## Usage

  Adapters are specified as `{Module, config}` tuples:

      {:ok, session} = ClaudeCode.start_link(
        adapter: {ClaudeCode.Adapter.Port, cli_path: "/usr/bin/claude"},
        model: "opus"
      )

  The default adapter is `ClaudeCode.Adapter.Port`.
  """

  @type adapter_config :: keyword()
  @type health :: :healthy | :degraded | {:unhealthy, reason :: term()}
  @doc """
  Starts the adapter process and provisions the execution environment.

  This should eagerly provision resources (find binary, start container, etc.)
  and return `{:error, reason}` immediately if provisioning fails.

  ## Parameters

  - `session` - PID of the Session GenServer
  - `adapter_config` - Adapter-specific configuration keyword list
  """
  @callback start_link(session :: pid(), adapter_config()) ::
              {:ok, pid()} | {:error, term()}

  @doc """
  Sends a query to the adapter.

  The adapter should send messages back to the session via the notification
  helpers (see module doc for the full protocol). Typical flow:

  - `notify_message/3` for each CLI message (Session auto-completes on ResultMessage)
  - `notify_error/3` on errors

  ## Parameters

  - `adapter` - PID of the adapter process
  - `request_id` - Unique reference for this request
  - `prompt` - The user's query string
  - `opts` - Query options (includes :session_id if resuming)
  """
  @callback send_query(
              adapter :: pid(),
              request_id :: reference(),
              prompt :: String.t(),
              opts :: keyword()
            ) :: :ok | {:error, term()}

  @doc """
  Returns the health status of the adapter's execution environment.
  """
  @callback health(adapter :: pid()) :: health()

  @doc """
  Stops the adapter and cleans up resources.
  """
  @callback stop(adapter :: pid()) :: :ok

  @doc """
  Sends a control request to the adapter and waits for a response.

  This is an optional callback — adapters that don't support the control
  protocol simply don't implement it. Use `function_exported?/3` to check.
  """
  @callback send_control_request(adapter :: pid(), subtype :: atom(), params :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Returns cached server initialization info from the control handshake.

  This is an optional callback.
  """
  @callback get_server_info(adapter :: pid()) :: {:ok, map() | nil} | {:error, term()}

  @doc """
  Sends an interrupt signal to stop the current generation.

  This is an optional, fire-and-forget callback — the CLI stops generating
  and emits a result message. No response is expected.
  """
  @callback interrupt(adapter :: pid()) :: :ok | {:error, term()}

  @optional_callbacks [send_control_request: 3, get_server_info: 1, interrupt: 1]

  # ============================================================================
  # Notification Helpers
  # ============================================================================

  @doc """
  Sends a message to the session for delivery.

  Accepts an already-parsed message struct, a raw JSON map, or a binary
  string. Structs are delivered directly; maps and binaries are decoded
  and parsed via `CLI.Parser`. Auto-completes the request when a
  `ResultMessage` is detected.
  """
  @spec notify_message(pid(), reference(), struct() | map() | binary()) :: :ok
  def notify_message(session, request_id, raw) do
    send(session, {:adapter_message, request_id, raw})
    :ok
  end

  @doc """
  Notifies the session that a request encountered an error.
  """
  @spec notify_error(pid(), reference(), term()) :: :ok
  def notify_error(session, request_id, reason) do
    send(session, {:adapter_error, request_id, reason})
    :ok
  end

  @doc """
  Notifies the session of an adapter status change.

  Status values:
  - `:provisioning` — adapter is starting up
  - `:ready` — adapter is ready to accept queries
  - `{:error, reason}` — provisioning failed
  """
  @spec notify_status(pid(), :provisioning | :ready | {:error, term()}) :: :ok
  def notify_status(session, status) do
    send(session, {:adapter_status, status})
    :ok
  end

  @doc """
  Forwards an inbound control request from adapter to session.
  """
  @spec notify_control_request(pid(), String.t(), map()) :: :ok
  def notify_control_request(session, request_id, request) do
    send(session, {:adapter_control_request, request_id, request})
    :ok
  end
end
