defmodule ClaudeCode.Adapter.Test do
  @moduledoc """
  Test adapter that delivers mock messages synchronously.

  This adapter retrieves messages from registered stubs in `ClaudeCode.Test`
  and sends them to the Session. Used for testing applications built on ClaudeCode.
  """

  @behaviour ClaudeCode.Adapter

  use GenServer

  # ============================================================================
  # Client API (Adapter Behaviour)
  # ============================================================================

  @impl ClaudeCode.Adapter
  def start_link(session, opts) do
    GenServer.start_link(__MODULE__, {session, opts})
  end

  @impl ClaudeCode.Adapter
  def send_query(adapter, request_id, prompt, opts) do
    GenServer.cast(adapter, {:query, request_id, prompt, opts})
    :ok
  end

  @impl ClaudeCode.Adapter
  def interrupt(_adapter) do
    :ok
  end

  @impl ClaudeCode.Adapter
  def health(_adapter) do
    :healthy
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
    stub_name = Keyword.fetch!(opts, :stub_name)
    # Use callers passed from Session (captured when Session was started from test process)
    callers = Keyword.get(opts, :callers, [])

    state = %{
      session: session,
      stub_name: stub_name,
      callers: callers
    }

    # Link to session for lifecycle management
    Process.link(session)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:query, request_id, prompt, opts}, state) do
    # Get messages from stub via ClaudeCode.Test, using captured callers
    messages = ClaudeCode.Test.stream(state.stub_name, prompt, opts, state.callers)

    # Send all messages to session
    Enum.each(messages, fn msg ->
      send(state.session, {:adapter_message, request_id, msg})
    end)

    send(state.session, {:adapter_done, request_id, :completed})

    {:noreply, state}
  end
end
