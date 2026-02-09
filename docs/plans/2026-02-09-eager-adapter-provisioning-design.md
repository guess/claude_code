# Eager Adapter Provisioning

**Status:** Implemented

## Problem

The CLI adapter currently lazy-connects on first query. Auto-install and port spawning happen when the first message is sent, not at session startup. This doesn't align with an adapter model where backends may need heavier provisioning (e.g., remote sandboxes that take time to spin up).

## Design

Move connection/provisioning to adapter startup time, with async provisioning and push-based status notifications.

### Adapter Helper Functions

Add notification helpers to `ClaudeCode.Adapter` that centralize the message protocol adapters use to communicate with Session:

```elixir
def notify_message(session, request_id, message)
def notify_done(session, request_id, reason)
def notify_error(session, request_id, reason)
def notify_status(session, status)
```

Status values: `:ready`, `:provisioning`, `{:error, reason}`

All existing raw `send/2` calls in adapters are replaced with these helpers. No new behaviour callbacks — these are functions adapters call, not callbacks they implement.

### CLI Adapter: Async Provisioning

`init` returns immediately and provisions via `handle_continue`:

```elixir
def init({session, opts}) do
  state = %__MODULE__{..., status: :provisioning}
  Process.link(session)
  Adapter.notify_status(session, :provisioning)
  {:ok, state, {:continue, :connect}}
end

def handle_continue(:connect, state) do
  case spawn_cli(state) do
    {:ok, port} ->
      Adapter.notify_status(state.session, :ready)
      {:noreply, %{state | port: port, status: :ready}}
    {:error, reason} ->
      Adapter.notify_status(state.session, {:error, reason})
      {:noreply, %{state | status: :disconnected}}
  end
end
```

### Race Condition Prevention

A `:status` field on the adapter state prevents double-provisioning if a query arrives while provisioning is in progress:

```elixir
defstruct [..., status: :provisioning]  # :provisioning | :ready | :disconnected
```

`ensure_connected` checks status:

- `:provisioning` — return `{:error, :provisioning}`, don't start a second connection
- `:disconnected` with `port: nil` — attempt reconnection (crash recovery, sandbox auto-shutoff)
- `:ready` — pass through

State machine: `:provisioning` -> `:ready` | `:disconnected`. Reconnection only from `:disconnected`.

### Session: Status-Aware Query Queuing

Session gains an `:adapter_status` field and handles status notifications:

- `{:adapter_status, :ready}` — process queued requests
- `{:adapter_status, :provisioning}` — record status
- `{:adapter_status, {:error, reason}}` — fail all queued requests

`enqueue_or_execute` gains a third condition:

```elixir
defp enqueue_or_execute(request, prompt, opts, state) do
  cond do
    state.adapter_status != :ready -> enqueue(request, prompt, opts, state)
    has_active_request?(state) -> enqueue(request, prompt, opts, state)
    true -> execute_request(request, prompt, opts, state)
  end
end
```

Queries sent during provisioning wait naturally. Errors only surface if provisioning fails.

### Test Adapter

Sends `Adapter.notify_status(session, :ready)` in its `init`. No provisioning phase needed. Replaces raw `send/2` with adapter helpers.

## Files Changed

| File | Change |
|------|--------|
| `lib/claude_code/adapter.ex` | Add `notify_message/3`, `notify_done/3`, `notify_error/3`, `notify_status/2` helpers |
| `lib/claude_code/adapter/cli.ex` | Add `:status` field, async provisioning via `handle_continue`, race-safe `ensure_connected`, use adapter helpers |
| `lib/claude_code/adapter/test.ex` | Send `notify_status(:ready)` in init, use adapter helpers |
| `lib/claude_code/session.ex` | Add `:adapter_status` field, handle `{:adapter_status, ...}`, queue queries when not ready, fail queue on error |

## What's NOT Changing

- Adapter behaviour callbacks (no new callbacks)
- Public API (`ClaudeCode.start_link`, `ClaudeCode.query`, etc.)
- Message types, content blocks, stream utilities
- Options validation

## Future Alignment

This design supports remote sandbox adapters where:
- Provisioning may take seconds (container spin-up)
- Sandboxes auto-shutoff after inactivity, requiring reconnection
- `{:adapter_status, :disconnected}` can signal sandbox shutdown
- `ensure_connected` handles transparent re-provisioning on next query
