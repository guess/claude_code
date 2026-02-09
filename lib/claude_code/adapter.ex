defmodule ClaudeCode.Adapter do
  @moduledoc """
  Behaviour for ClaudeCode adapters.

  Adapters handle the full lifecycle of a Claude Code execution environment:
  provisioning, communication, health checking, interruption, and cleanup.

  ## Message Protocol

  Adapters communicate with Session using the notification helpers:

  - `notify_message(session, request_id, message)` - A parsed message from Claude
  - `notify_done(session, request_id, reason)` - Query complete (reason: :completed | :interrupted)
  - `notify_error(session, request_id, reason)` - Error occurred
  - `notify_status(session, status)` - Adapter status change (:provisioning | :ready | {:error, reason})

  ## Usage

  Adapters are specified as `{Module, config}` tuples:

      {:ok, session} = ClaudeCode.start_link(
        adapter: {ClaudeCode.Adapter.Local, cli_path: "/usr/bin/claude"},
        model: "opus"
      )

  The default adapter is `ClaudeCode.Adapter.Local`.
  """

  @type adapter_config :: keyword()
  @type health :: :healthy | :degraded | {:unhealthy, reason :: term()}
  @type done_reason :: :completed | :interrupted

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

  The adapter should send messages back to the session via `send/2`:

  - `{:adapter_message, request_id, message}` for each message
  - `{:adapter_done, request_id, reason}` when the query completes
  - `{:adapter_error, request_id, reason}` on errors

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
  Interrupts the currently executing query.

  This signals the backend to stop processing (e.g., SIGINT for CLI).
  The adapter should send `{:adapter_done, request_id, :interrupted}` after
  the query is interrupted. This is a clean end-of-stream, not an error.
  """
  @callback interrupt(adapter :: pid()) :: :ok | {:error, term()}

  @doc """
  Returns the health status of the adapter's execution environment.
  """
  @callback health(adapter :: pid()) :: health()

  @doc """
  Stops the adapter and cleans up resources.
  """
  @callback stop(adapter :: pid()) :: :ok

  # ============================================================================
  # Notification Helpers
  # ============================================================================

  @doc """
  Sends a parsed message to the session for a specific request.
  """
  @spec notify_message(pid(), reference(), term()) :: :ok
  def notify_message(session, request_id, message) do
    send(session, {:adapter_message, request_id, message})
    :ok
  end

  @doc """
  Notifies the session that a request has completed.
  """
  @spec notify_done(pid(), reference(), done_reason()) :: :ok
  def notify_done(session, request_id, reason) do
    send(session, {:adapter_done, request_id, reason})
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
end
