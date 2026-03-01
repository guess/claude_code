# Adapter.Node Design — Distributed Sessions via BEAM

**Date:** 2026-02-28
**Status:** Draft

## Goal

Add `Adapter.Node` — a distributed adapter that runs `Adapter.Port` (formerly `Adapter.Local`) on a remote BEAM node. Uses Erlang distribution for transport. No custom protocol, no sidecar package, no WebSocket.

## Adapter Naming Convention

Rename adapters to reflect their transport mechanism:

| Current Name | New Name | Transport |
|---|---|---|
| `Adapter.Local` | `Adapter.Port` | Erlang Port (stdin/stdout) |
| `Adapter.Remote` | `Adapter.WebSocket` | WebSocket via Mint |
| *(new)* | `Adapter.Node` | BEAM distribution |
| `Adapter.Test` | `Adapter.Test` | In-memory stubs |

The rename is a separate PR from the new adapter.

## Architecture

```
Local BEAM Node                     Remote BEAM Node
┌──────────────┐  GenServer.call   ┌──────────────────┐
│   Session    │ ─────────────────→│  Adapter.Port    │
│              │  send(session,msg) │    (CLI Port)    │
│              │ ←─────────────────│                  │
└──────────────┘  distributed link  └──────────────────┘
```

`Adapter.Node` is a factory — not a long-lived process. It connects to the remote node, creates a workspace directory, starts `Adapter.Port` there, and returns the remote PID. After startup, Session talks directly to the remote `Adapter.Port` via standard BEAM mechanisms.

Key insight: `send/2` and `GenServer.call/2` work transparently across connected BEAM nodes. `Process.link/1` creates distributed links that fire on nodedown. The adapter contract already works across nodes with zero changes to Session.

## Configuration

The adapter is configured via the `adapter: {Module, config}` tuple pattern. Session passes `config` directly to `start_link/2` — it does not merge session-level options. So the adapter config must include everything the remote `Adapter.Port` needs.

```elixir
adapter: {ClaudeCode.Adapter.Node, [
  # Node-specific (consumed by Adapter.Node, not forwarded)
  node: :"claude@gpu-server",         # Required — remote node name
  workspace_path: "/workspaces/t-123", # Required — working directory on remote node
  cookie: :my_secret_cookie,           # Optional — Erlang cookie (if not already set)
  connect_timeout: 5_000,              # Optional — timeout for Node.connect (default: 5s)

  # Pass-through to Adapter.Port on the remote node
  model: "claude-sonnet-4-20250514",
  system_prompt: "You are helpful.",
  # ... any standard Adapter.Port option
]}
```

## Implementation

~55 lines of code. The adapter:

1. Sets cookie if provided
2. Connects to remote node with timeout
3. Creates workspace directory on remote node via RPC
4. Starts `Adapter.Port` on remote node via RPC, passing the local Session PID
5. Returns `{:ok, remote_pid}`

All query/health/stop/interrupt calls delegate directly to `Adapter.Port` — the functions just do `GenServer.call(pid, ...)` which works for remote PIDs.

```elixir
defmodule ClaudeCode.Adapter.Node do
  @behaviour ClaudeCode.Adapter

  @node_opts [:node, :cookie, :workspace_path, :connect_timeout]

  def start_link(session, config) do
    node = Keyword.fetch!(config, :node)
    cookie = Keyword.get(config, :cookie)
    workspace = Keyword.fetch!(config, :workspace_path)
    timeout = Keyword.get(config, :connect_timeout, 5_000)

    if cookie, do: Node.set_cookie(node, cookie)

    with :ok <- connect_node(node, timeout),
         :ok <- ensure_workspace(node, workspace) do
      adapter_opts =
        config
        |> Keyword.drop(@node_opts)
        |> Keyword.put(:cwd, workspace)

      case :rpc.call(node, ClaudeCode.Adapter.Port, :start_link, [session, adapter_opts]) do
        {:ok, pid} -> {:ok, pid}
        {:error, _} = err -> err
        {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
      end
    end
  end

  defdelegate send_query(adapter, request_id, prompt, opts), to: ClaudeCode.Adapter.Port
  defdelegate health(adapter), to: ClaudeCode.Adapter.Port
  defdelegate stop(adapter), to: ClaudeCode.Adapter.Port
  defdelegate interrupt(adapter), to: ClaudeCode.Adapter.Port
  defdelegate send_control_request(adapter, subtype, params), to: ClaudeCode.Adapter.Port
  defdelegate get_server_info(adapter), to: ClaudeCode.Adapter.Port

  defp connect_node(node, timeout) do
    task = Task.async(fn -> Node.connect(node) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, {:node_connect_failed, node}}
      nil -> {:error, {:connect_timeout, node}}
    end
  end

  defp ensure_workspace(node, path) do
    case :rpc.call(node, File, :mkdir_p, [path]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:workspace_failed, reason}}
      {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
    end
  end
end
```

## Usage

```elixir
{:ok, session} = ClaudeCode.Session.start_link(
  adapter: {ClaudeCode.Adapter.Node, [
    node: :"claude@gpu-server",
    cookie: :my_secret,
    workspace_path: "/workspaces/tenant-123",
    model: "claude-sonnet-4-20250514"
  ]}
)

# Works identically to a local session
{:ok, result} = ClaudeCode.Session.query(session, "Hello!")

# Streaming works too
session
|> ClaudeCode.Session.stream("Explain OTP")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

All options live inside the adapter tuple. `Adapter.Node` strips its own keys (`:node`, `:cookie`, `:workspace_path`, `:connect_timeout`) and forwards the rest to `Adapter.Port` on the remote node.

## Failure Handling

**Remote node goes down:** The distributed link fires. Session receives `{:EXIT, remote_pid, :noconnection}` and handles it the same way it handles a local adapter crash — completes the active request with an error.

**Network partition:** Same as nodedown from BEAM's perspective. Link fires, adapter is dead. User creates a new Session to reconnect.

**RPC failure during startup:** `Node.connect/1` returns `false` or `:rpc.call` returns `{:badrpc, reason}`. Returned as `{:error, ...}` from `start_link/2`.

**Remote CLI not found:** `Adapter.Port` fails to resolve the CLI binary on the remote node. Error propagates through RPC back to caller.

**No automatic reconnection in v1.** Reconnection across nodes requires resuming CLI state, which adds significant complexity. Sessions are cheap to create — the user can start a new one.

## What Runs Where

| Component | Node | Notes |
|---|---|---|
| Session | Local | Manages lifecycle, parses messages |
| Adapter.Node | Local | Factory only — no long-lived process |
| Adapter.Port | Remote | Owns CLI Port, sends raw JSON to Session |
| CLI subprocess | Remote | Spawned by Adapter.Port via Erlang Port |
| Hooks | Remote | Run where the CLI runs |

## What This Replaces

`Adapter.Node` serves the same use case as `Adapter.WebSocket` + sidecar package but with ~95% less code:

| | WebSocket approach | Node approach |
|---|---|---|
| Adapter code | ~570 lines | ~55 lines |
| Protocol layer | ~120 lines | 0 (BEAM handles it) |
| Sidecar package | ~400 lines + configs | 0 (Adapter.Port runs directly) |
| Wire format | JSON envelopes | Erlang term distribution |
| Auth | Bearer token | Erlang cookie |
| Dependencies | mint_web_socket | None (stdlib) |

The WebSocket approach remains useful if non-Elixir clients need to connect. For Elixir-to-Elixir, `Adapter.Node` is simpler.

## Future Additions (not in v1)

- **Session limits:** Add a `DynamicSupervisor` on the remote node, start adapters under it, use `count_children` for limits (~30 lines)
- **Reconnection:** Monitor remote node, reconnect and resume session on recovery
- **Workspace cleanup:** Periodic cleanup of stale workspace directories
- **Node pool:** Round-robin across multiple remote nodes for load distribution

## Testing Strategy

**Unit tests:**
- Config validation (missing node, missing workspace_path)
- Cookie setting
- Connect timeout handling
- RPC error handling (badrpc wrapping)

**Integration tests (requires two BEAM nodes):**
- Start a local peer node via `:peer.start/1` (OTP 25+)
- Full lifecycle: connect → start adapter → query → receive messages → stop
- Nodedown handling: stop peer node mid-query, verify Session gets error
- Workspace creation on remote node

**No new mocks needed** — `:peer` module provides real isolated nodes for testing.
