defmodule ClaudeCode.Adapter do
  @moduledoc """
  Behaviour for ClaudeCode adapters.

  Adapters handle the communication layer between Session and Claude.
  The CLI adapter (`ClaudeCode.Adapter.CLI`) manages a persistent Port subprocess.
  The Test adapter (`ClaudeCode.Adapter.Test`) provides mock message delivery for testing.

  ## Message Protocol

  Adapters communicate with Session by sending messages:

  - `{:adapter_message, request_id, message}` - A parsed message from Claude
  - `{:adapter_done, request_id}` - Query complete (ResultMessage received)
  - `{:adapter_error, request_id, reason}` - Error occurred

  ## Usage

  To use a custom adapter, pass the `:adapter` option when starting a session:

      # For testing with stubs
      {:ok, session} = ClaudeCode.start_link(
        adapter: {ClaudeCode.Test, MyApp.Chat}
      )

  The default adapter is `ClaudeCode.Adapter.CLI` which manages the Claude CLI subprocess.
  """

  @doc """
  Starts the adapter process.

  The adapter should link to the session for lifecycle management.
  Returns `{:ok, pid}` on success.

  ## Parameters

  - `session` - PID of the Session GenServer
  - `opts` - Session options (api_key, model, etc.)
  """
  @callback start_link(session :: pid(), opts :: keyword()) ::
              {:ok, pid()} | {:error, term()}

  @doc """
  Sends a query to the adapter.

  The adapter should send messages back to the session via `send/2`:

  - `{:adapter_message, request_id, message}` for each message
  - `{:adapter_done, request_id}` when the query completes
  - `{:adapter_error, request_id, reason}` on errors

  ## Parameters

  - `adapter` - PID of the adapter process
  - `request_id` - Unique reference for this request
  - `prompt` - The user's query string
  - `session_id` - Optional session ID for conversation continuity
  - `opts` - Query options
  """
  @callback send_query(
              adapter :: pid(),
              request_id :: reference(),
              prompt :: String.t(),
              session_id :: String.t() | nil,
              opts :: keyword()
            ) :: :ok | {:error, term()}

  @doc """
  Stops the adapter gracefully.
  """
  @callback stop(adapter :: pid()) :: :ok
end
