# Eager Adapter Provisioning — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move adapter connection/provisioning from lazy (first query) to eager (startup), with async provisioning and push-based status notifications.

**Architecture:** Adapters provision asynchronously via `handle_continue`, sending status notifications to Session. Session queues queries until the adapter reports `:ready`. Adapter helper functions centralize the message protocol. Existing `ensure_connected` stays as a reconnection fallback.

**Tech Stack:** Elixir GenServer, `handle_continue/2`, existing Adapter behaviour

---

### Task 1: Add Adapter Notification Helpers

**Files:**
- Modify: `lib/claude_code/adapter.ex`
- Test: `test/claude_code/adapter_test.exs`

**Step 1: Write tests for the notification helpers**

Add to `test/claude_code/adapter_test.exs`:

```elixir
describe "notification helpers" do
  test "notify_message/3 sends adapter_message to session" do
    session = self()
    request_id = make_ref()
    message = %{type: :test}

    ClaudeCode.Adapter.notify_message(session, request_id, message)

    assert_receive {:adapter_message, ^request_id, ^message}
  end

  test "notify_done/3 sends adapter_done to session" do
    session = self()
    request_id = make_ref()

    ClaudeCode.Adapter.notify_done(session, request_id, :completed)

    assert_receive {:adapter_done, ^request_id, :completed}
  end

  test "notify_error/3 sends adapter_error to session" do
    session = self()
    request_id = make_ref()

    ClaudeCode.Adapter.notify_error(session, request_id, :timeout)

    assert_receive {:adapter_error, ^request_id, :timeout}
  end

  test "notify_status/2 sends adapter_status to session" do
    session = self()

    ClaudeCode.Adapter.notify_status(session, :ready)
    assert_receive {:adapter_status, :ready}

    ClaudeCode.Adapter.notify_status(session, :provisioning)
    assert_receive {:adapter_status, :provisioning}

    ClaudeCode.Adapter.notify_status(session, {:error, :cli_not_found})
    assert_receive {:adapter_status, {:error, :cli_not_found}}
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/adapter_test.exs -v`
Expected: FAIL — `notify_message/3`, `notify_done/3`, `notify_error/3`, `notify_status/2` are undefined.

**Step 3: Implement the notification helpers**

Add to `lib/claude_code/adapter.ex` after the `@callback` definitions, before the closing `end`:

```elixir
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
```

Also update the moduledoc `## Message Protocol` section to mention the helpers:

Replace the current message protocol docs (lines 8-14) with:

```elixir
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
      adapter: {ClaudeCode.Adapter.CLI, cli_path: "/usr/bin/claude"},
      model: "opus"
    )

The default adapter is `ClaudeCode.Adapter.CLI`.
"""
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter_test.exs -v`
Expected: PASS

**Step 5: Run quality checks**

Run: `mix quality`
Expected: PASS (no warnings, no credo issues)

**Step 6: Commit**

```bash
git add lib/claude_code/adapter.ex test/claude_code/adapter_test.exs
git commit -m "feat: add notification helpers to Adapter module"
```

---

### Task 2: Migrate Test Adapter to Use Notification Helpers

**Files:**
- Modify: `lib/claude_code/adapter/test.ex`
- Test: `test/claude_code/adapter/test_adapter_test.exs` (existing tests should still pass)

**Step 1: Read the existing test adapter test file to understand what's covered**

Read `test/claude_code/adapter/test_adapter_test.exs` to understand the current test coverage before modifying.

**Step 2: Replace raw `send/2` calls with adapter helpers**

In `lib/claude_code/adapter/test.ex`, make these changes:

1. Add alias at top of module:
```elixir
alias ClaudeCode.Adapter
```

2. In `init/1`, add `notify_status(:ready)` after `Process.link(session)`:
```elixir
Process.link(session)
Adapter.notify_status(session, :ready)
```

3. In `handle_cast({:query, ...})`, replace the raw `send/2` calls:

Replace:
```elixir
Enum.each(messages, fn msg ->
  send(state.session, {:adapter_message, request_id, msg})
end)

send(state.session, {:adapter_done, request_id, :completed})
```

With:
```elixir
Enum.each(messages, fn msg ->
  Adapter.notify_message(state.session, request_id, msg)
end)

Adapter.notify_done(state.session, request_id, :completed)
```

**Step 3: Run existing test adapter tests**

Run: `mix test test/claude_code/adapter/test_adapter_test.exs -v`
Expected: PASS (no behavior change)

**Step 4: Run session tests that use the test adapter**

Run: `mix test test/claude_code/session_test.exs -v`
Expected: These will FAIL because Session doesn't handle `{:adapter_status, :ready}` yet. That's expected — we'll fix this in Task 4. Note the failures and move on.

**Step 5: Commit**

```bash
git add lib/claude_code/adapter/test.ex
git commit -m "refactor: migrate test adapter to use notification helpers"
```

---

### Task 3: Migrate CLI Adapter to Async Provisioning with Notification Helpers

**Files:**
- Modify: `lib/claude_code/adapter/cli.ex`
- Test: `test/claude_code/adapter/cli_test.exs`

**Step 1: Write tests for the new status field and provisioning behavior**

Add a new describe block to `test/claude_code/adapter/cli_test.exs`:

```elixir
describe "adapter status lifecycle" do
  test "starts in provisioning status and transitions to ready" do
    # Use a simple mock script that stays alive
    {:ok, context} =
      MockCLI.setup_with_script("""
      #!/bin/bash
      while IFS= read -r line; do
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
      done
      exit 0
      """)

    session = self()

    {:ok, adapter} =
      ClaudeCode.Adapter.CLI.start_link(session, [
        api_key: "test-key",
        cli_path: context[:mock_script]
      ])

    # Should receive provisioning then ready
    assert_receive {:adapter_status, :provisioning}, 1000
    assert_receive {:adapter_status, :ready}, 5000

    # State should reflect ready
    state = :sys.get_state(adapter)
    assert state.status == :ready
    assert state.port != nil

    GenServer.stop(adapter)
  end

  test "transitions to disconnected on provisioning failure" do
    session = self()

    {:ok, adapter} =
      ClaudeCode.Adapter.CLI.start_link(session, [
        api_key: "test-key",
        cli_path: "/nonexistent/path/to/claude"
      ])

    assert_receive {:adapter_status, :provisioning}, 1000
    assert_receive {:adapter_status, {:error, _reason}}, 5000

    state = :sys.get_state(adapter)
    assert state.status == :disconnected
    assert state.port == nil

    GenServer.stop(adapter)
  end

  test "ensure_connected returns error during provisioning" do
    # Start adapter with a script that takes a moment
    {:ok, context} =
      MockCLI.setup_with_script("""
      #!/bin/bash
      sleep 10
      while IFS= read -r line; do
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
      done
      exit 0
      """)

    session = self()

    {:ok, adapter} =
      ClaudeCode.Adapter.CLI.start_link(session, [
        api_key: "test-key",
        cli_path: context[:mock_script]
      ])

    assert_receive {:adapter_status, :provisioning}, 1000

    # Try to query immediately — should get :provisioning error
    result =
      ClaudeCode.Adapter.CLI.send_query(adapter, make_ref(), "test", [])

    assert {:error, :provisioning} = result

    GenServer.stop(adapter)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/adapter/cli_test.exs --only describe:"adapter status lifecycle" -v`
Expected: FAIL — no `status` field, no `handle_continue`, etc.

**Step 3: Implement the changes to the CLI adapter**

In `lib/claude_code/adapter/cli.ex`:

1. Add alias at top:
```elixir
alias ClaudeCode.Adapter
```

2. Add `:status` to defstruct:
```elixir
defstruct [
  :session,
  :session_options,
  :port,
  :buffer,
  :current_request,
  :api_key,
  status: :provisioning
]
```

3. Replace `init/1`:
```elixir
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
```

4. Add `handle_continue/2`:
```elixir
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
```

5. Update `ensure_connected` to be race-safe:
```elixir
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
```

6. Update port exit handlers to set status to `:disconnected`:

In `handle_info({port, {:exit_status, status}}, ...)`:
```elixir
{:noreply, %{state | port: nil, current_request: nil, buffer: "", status: :disconnected}}
```

In `handle_info({:DOWN, ...}, ...)`:
```elixir
{:noreply, %{state | port: nil, current_request: nil, buffer: "", status: :disconnected}}
```

7. Replace raw `send/2` calls with adapter helpers:

In `process_line/2`, replace:
```elixir
send(state.session, {:adapter_message, state.current_request, message})
```
with:
```elixir
Adapter.notify_message(state.session, state.current_request, message)
```

Replace:
```elixir
send(state.session, {:adapter_done, state.current_request, :completed})
```
with:
```elixir
Adapter.notify_done(state.session, state.current_request, :completed)
```

In `handle_info({port, {:exit_status, status}}, ...)`, replace:
```elixir
send(state.session, {:adapter_error, state.current_request, {:cli_exit, status}})
```
with:
```elixir
Adapter.notify_error(state.session, state.current_request, {:cli_exit, status})
```

In `handle_info({:DOWN, ...}, ...)`, replace:
```elixir
send(state.session, {:adapter_error, state.current_request, {:port_closed, reason}})
```
with:
```elixir
Adapter.notify_error(state.session, state.current_request, {:port_closed, reason})
```

In `handle_call(:interrupt, ...)`, replace:
```elixir
send(state.session, {:adapter_done, request_id, :interrupted})
```
with:
```elixir
Adapter.notify_done(state.session, request_id, :interrupted)
```

8. Update `handle_call(:health, ...)` to use status:
```elixir
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
```

**Step 4: Run the CLI adapter tests**

Run: `mix test test/claude_code/adapter/cli_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/claude_code/adapter/cli.ex test/claude_code/adapter/cli_test.exs
git commit -m "feat: async provisioning with status notifications in CLI adapter"
```

---

### Task 4: Update Session to Handle Adapter Status

**Files:**
- Modify: `lib/claude_code/session.ex`
- Test: `test/claude_code/session_adapter_test.exs`

**Step 1: Write tests for session status handling**

Add a new describe block to `test/claude_code/session_adapter_test.exs`:

```elixir
describe "adapter status handling" do
  defmodule SlowProvisioningAdapter do
    @moduledoc false
    @behaviour ClaudeCode.Adapter
    use GenServer

    alias ClaudeCode.Adapter

    @impl ClaudeCode.Adapter
    def start_link(session, opts), do: GenServer.start_link(__MODULE__, {session, opts})

    @impl ClaudeCode.Adapter
    def send_query(adapter, request_id, prompt, opts) do
      GenServer.cast(adapter, {:query, request_id, prompt, opts})
      :ok
    end

    @impl ClaudeCode.Adapter
    def interrupt(_adapter), do: :ok

    @impl ClaudeCode.Adapter
    def health(_adapter), do: :healthy

    @impl ClaudeCode.Adapter
    def stop(adapter), do: GenServer.stop(adapter, :normal)

    @impl GenServer
    def init({session, opts}) do
      Process.link(session)
      delay = Keyword.get(opts, :provisioning_delay, 200)
      Adapter.notify_status(session, :provisioning)
      {:ok, %{session: session, delay: delay}, {:continue, :provision}}
    end

    @impl GenServer
    def handle_continue(:provision, state) do
      Process.sleep(state.delay)
      Adapter.notify_status(state.session, :ready)
      {:noreply, state}
    end

    @impl GenServer
    def handle_cast({:query, request_id, _prompt, _opts}, state) do
      Adapter.notify_message(state.session, request_id, %ClaudeCode.Message.ResultMessage{
        result: "provisioned response",
        is_error: false,
        subtype: nil,
        session_id: "test-session",
        duration_ms: 50,
        duration_api_ms: 40,
        num_turns: 1,
        total_cost_usd: 0.001,
        usage: %{}
      })
      Adapter.notify_done(state.session, request_id, :completed)
      {:noreply, state}
    end
  end

  test "queries sent during provisioning are queued and executed after ready" do
    {:ok, session} =
      ClaudeCode.Session.start_link(
        adapter: {SlowProvisioningAdapter, [provisioning_delay: 200]}
      )

    # Send query immediately (adapter still provisioning)
    result =
      session
      |> ClaudeCode.stream("test")
      |> ClaudeCode.Stream.final_text()

    assert result == "provisioned response"

    GenServer.stop(session)
  end

  test "multiple queries during provisioning all get processed" do
    {:ok, session} =
      ClaudeCode.Session.start_link(
        adapter: {SlowProvisioningAdapter, [provisioning_delay: 200]}
      )

    # Send 3 queries concurrently during provisioning
    tasks =
      Enum.map(1..3, fn _i ->
        Task.async(fn ->
          session
          |> ClaudeCode.stream("test")
          |> ClaudeCode.Stream.final_text()
        end)
      end)

    results = Enum.map(tasks, &Task.await(&1, 5000))

    assert Enum.all?(results, &(&1 == "provisioned response"))

    GenServer.stop(session)
  end

  defmodule FailingProvisioningAdapter do
    @moduledoc false
    @behaviour ClaudeCode.Adapter
    use GenServer

    alias ClaudeCode.Adapter

    @impl ClaudeCode.Adapter
    def start_link(session, opts), do: GenServer.start_link(__MODULE__, {session, opts})

    @impl ClaudeCode.Adapter
    def send_query(adapter, request_id, prompt, opts) do
      GenServer.cast(adapter, {:query, request_id, prompt, opts})
      :ok
    end

    @impl ClaudeCode.Adapter
    def interrupt(_adapter), do: :ok

    @impl ClaudeCode.Adapter
    def health(_adapter), do: :healthy

    @impl ClaudeCode.Adapter
    def stop(adapter), do: GenServer.stop(adapter, :normal)

    @impl GenServer
    def init({session, _opts}) do
      Process.link(session)
      Adapter.notify_status(session, :provisioning)
      {:ok, %{session: session}, {:continue, :provision}}
    end

    @impl GenServer
    def handle_continue(:provision, state) do
      Process.sleep(100)
      Adapter.notify_status(state.session, {:error, :sandbox_unavailable})
      {:noreply, state}
    end

    @impl GenServer
    def handle_cast({:query, _request_id, _prompt, _opts}, state) do
      {:noreply, state}
    end
  end

  test "queued queries fail when provisioning fails" do
    {:ok, session} =
      ClaudeCode.Session.start_link(
        adapter: {FailingProvisioningAdapter, []}
      )

    # Send query during provisioning — should eventually get an error
    thrown =
      catch_throw(
        session
        |> ClaudeCode.stream("test")
        |> Enum.to_list()
      )

    assert {:stream_error, {:provisioning_failed, :sandbox_unavailable}} = thrown

    GenServer.stop(session)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/session_adapter_test.exs --only describe:"adapter status handling" -v`
Expected: FAIL — Session doesn't handle `{:adapter_status, ...}` or have `adapter_status` field.

**Step 3: Implement Session changes**

In `lib/claude_code/session.ex`:

1. Add `:adapter_status` to defstruct:
```elixir
defstruct [
  :session_options,
  :session_id,
  :tool_callback,
  :pending_tool_uses,
  # Adapter
  :adapter_module,
  :adapter_opts,
  :adapter_pid,
  adapter_status: :provisioning,
  # Request tracking
  :requests,
  :query_queue,
  # Caller chain for test adapter stub lookup
  :callers
]
```

2. Update `init/1` — remove the assumption that adapter is immediately ready. The `adapter_status` defaults to `:provisioning` via defstruct, which is correct. The adapter will send `{:adapter_status, :ready}` when ready.

3. Add `handle_info` clauses for adapter status (add before the existing `handle_info` for `{:adapter_message, ...}`):

```elixir
def handle_info({:adapter_status, :ready}, state) do
  new_state = %{state | adapter_status: :ready}
  {:noreply, process_next_in_queue(new_state)}
end

def handle_info({:adapter_status, :provisioning}, state) do
  {:noreply, %{state | adapter_status: :provisioning}}
end

def handle_info({:adapter_status, {:error, reason}}, state) do
  new_state = fail_queued_requests(state, {:provisioning_failed, reason})
  {:noreply, %{new_state | adapter_status: {:error, reason}}}
end
```

4. Update `enqueue_or_execute/4` to check adapter status:

```elixir
defp enqueue_or_execute(request, prompt, opts, state) do
  cond do
    state.adapter_status != :ready ->
      enqueue_request(request, prompt, opts, state)

    has_active_request?(state) ->
      enqueue_request(request, prompt, opts, state)

    true ->
      execute_request(request, prompt, opts, state)
  end
end
```

5. Extract the enqueue logic into a helper (currently inline in `enqueue_or_execute`):

```elixir
defp enqueue_request(request, prompt, opts, state) do
  queued_request = %{request | status: :queued}
  queue = :queue.in({request, prompt, opts}, state.query_queue)
  new_requests = Map.put(state.requests, request.id, queued_request)
  {:ok, %{state | query_queue: queue, requests: new_requests}}
end
```

6. Add `fail_queued_requests/2`:

```elixir
defp fail_queued_requests(state, reason) do
  # Fail all queued requests
  {items, empty_queue} = drain_queue(state.query_queue)

  new_requests =
    Enum.reduce(items, state.requests, fn {request, _prompt, _opts}, requests ->
      case Map.get(requests, request.id) do
        nil ->
          requests

        tracked_request ->
          notify_error(tracked_request, reason)
          Map.put(requests, request.id, %{tracked_request | status: :completed})
      end
    end)

  %{state | requests: new_requests, query_queue: empty_queue}
end

defp drain_queue(queue) do
  drain_queue(queue, [])
end

defp drain_queue(queue, acc) do
  case :queue.out(queue) do
    {{:value, item}, rest} -> drain_queue(rest, [item | acc])
    {:empty, empty} -> {Enum.reverse(acc), empty}
  end
end
```

**Step 4: Run the new session adapter tests**

Run: `mix test test/claude_code/session_adapter_test.exs -v`
Expected: PASS

**Step 5: Run all session tests to check for regressions**

Run: `mix test test/claude_code/session_test.exs -v`
Expected: PASS — the test adapter now sends `:ready` immediately so tests work as before.

**Step 6: Commit**

```bash
git add lib/claude_code/session.ex test/claude_code/session_adapter_test.exs
git commit -m "feat: session queues queries until adapter reports ready"
```

---

### Task 5: Update Existing Error Handling Test

**Files:**
- Modify: `test/claude_code/session_test.exs`

**Step 1: Update the "handles CLI not found" test**

The current test at `test/claude_code/session_test.exs:259-278` expects that `Session.start_link` succeeds with a bad `cli_path` and the error surfaces on first query. With eager provisioning, the CLI adapter now provisions asynchronously — the error surfaces via `{:adapter_status, {:error, reason}}`, which fails queued queries.

The test should still work because:
1. `start_link` succeeds (adapter starts, provisioning is async)
2. `spawn_cli` fails during `handle_continue` → sends `{:adapter_status, {:error, ...}}`
3. Session fails the queued stream request

However, the error shape may change. The stream will now throw `{:stream_error, {:provisioning_failed, {:cli_not_found, message}}}` instead of `{:stream_init_error, {:cli_not_found, message}}`.

Update the test:

```elixir
test "handles CLI not found" do
  {:ok, session} =
    Session.start_link(
      api_key: "test-key",
      cli_path: "/nonexistent/path/to/claude"
    )

  thrown =
    session
    |> ClaudeCode.stream("test")
    |> Enum.to_list()
    |> catch_throw()

  assert {:stream_error, {:provisioning_failed, {:cli_not_found, message}}} = thrown
  assert message =~ "Claude CLI not found"

  GenServer.stop(session)
end
```

**Step 2: Run the test**

Run: `mix test test/claude_code/session_test.exs --only test:"handles CLI not found" -v`
Expected: PASS

**Step 3: Commit**

```bash
git add test/claude_code/session_test.exs
git commit -m "test: update CLI not found test for async provisioning"
```

---

### Task 6: Full Test Suite and Quality Check

**Files:** None (validation only)

**Step 1: Run the full test suite**

Run: `mix test`
Expected: All tests PASS

**Step 2: Run quality checks**

Run: `mix quality`
Expected: PASS — no compiler warnings, format is clean, credo passes, dialyzer passes.

**Step 3: Fix any failures**

If any tests fail, investigate and fix. Common issues:
- Tests using `ConfigCapturingAdapter` or `HealthyAdapter` in `session_adapter_test.exs` may need to send `{:adapter_status, :ready}` in their `init` since Session now queues until ready.
- The `interrupt end-to-end` test may need adjustment if timing changes.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test suite regressions from async provisioning"
```

---

### Task 7: Update Design Doc

**Files:**
- Modify: `docs/plans/2026-02-09-eager-adapter-provisioning-design.md`

**Step 1: Add "Implemented" status to design doc header**

Add at the top of the design doc after the title:

```markdown
**Status:** Implemented
```

**Step 2: Commit**

```bash
git add docs/plans/2026-02-09-eager-adapter-provisioning-design.md
git commit -m "docs: mark eager provisioning design as implemented"
```
