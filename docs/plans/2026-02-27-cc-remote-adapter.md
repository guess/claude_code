# ClaudeCode Remote Adapter — Design

**Date**: 2026-02-27
**Status**: Approved
**Package**: `claude_code` hex package
**Context**: [2026-02-27-agent-roadmap.md](2026-02-27-agent-roadmap.md)

## Overview

A new adapter for the `claude_code` hex package that runs CC sessions on a remote server instead of locally. The host application connects via WebSocket; a persistent "agent runner" service on a dedicated server manages CC sessions, workspaces, and sandboxing.

This keeps agent workloads off the main application server without the complexity of per-run container orchestration.

## Naming

**`ClaudeCode.Adapter.Remote`** — not "Container". The adapter connects to a remote execution environment over WebSocket. It doesn't care whether the other end is a Docker container, a Dokku app, a bare-metal server, or a cloud function.

## Separation of Concerns

The **adapter** is protocol-only. It connects to a WebSocket URL, sends/receives JSON messages, and implements the `ClaudeCode.Adapter` behaviour. It does NOT provision servers, manage Docker images, or know anything about deployment topology.

The **sidecar** is a separate deployable application. It accepts WebSocket connections, runs local CC sessions on behalf of remote callers, manages workspace directories, and optionally sandboxes Bash execution.

## Architecture

```
Host Application (e.g. qultr-api on Server A)
  ├── ClaudeCode.Session (GenServer) — unchanged
  └── ClaudeCode.Adapter.Remote (GenServer)
        └── WebSocket client → connects to sidecar

Agent Runner (Server B — dedicated server)
  ├── ClaudeCode.Remote.Sidecar (persistent Elixir app)
  │   ├── WebSocket server (Bandit + WebSock)
  │   ├── Session manager — one CC session per WebSocket connection
  │   └── Workspace manager — /workspaces/<id>/ per agent
  ├── Per active session:
  │   ├── ClaudeCode.Adapter.Local → CC CLI subprocess
  │   ├── Workspace directory (persistent, git-managed)
  │   └── Sandbox (bubblewrap) for Bash tool execution
  └── Shared: Node.js, CC CLI binary, Git, Python, tools
```

### Key Properties

- **Persistent service** — the agent runner is always running. No per-run startup cost
- **Session = WebSocket connection** — each connection from the host maps to one CC session on the runner
- **Filesystem isolation** — workspaces are separate directories. Bubblewrap sandboxes Bash execution
- **Transparent API** — `ClaudeCode.stream/2`, hooks, sessions, cost tracking all work identically

## Design Decisions

| Decision              | Choice                             | Rationale                                                                      |
| --------------------- | ---------------------------------- | ------------------------------------------------------------------------------ |
| Naming                | `Adapter.Remote` (not Container)   | It's about remote execution, not containers specifically                       |
| Adapter scope         | Protocol-only                      | Adapter owns WebSocket protocol. Deployment/provisioning is the user's problem |
| Deployment model      | Single persistent service          | No container orchestration. Zero provisioning latency. Deploy like any app     |
| Bridge protocol       | WebSocket (JSON)                   | Bidirectional, well-understood. Same NDJSON format as local adapter            |
| Sandbox               | Bubblewrap / filesystem namespaces | Lightweight, Linux-native. Agents are our own code, not untrusted              |
| Workspace persistence | Directories on disk                | Trivial. Git-managed snapshots per run                                         |
| Hooks                 | Run on sidecar (agent runner)      | No round-trip. Hook config serialized in init message                          |
| Code location         | Separate packages in same repo     | Adapter in `claude_code`; sidecar in `claude_code_sidecar` (released independently) |
| WS client (adapter)   | `mint_web_socket`                  | Built on Mint (common transitive dep). Process-less, fits GenServer adapter    |
| WS server (sidecar)   | `bandit` + `websock`               | Standard Elixir WebSocket server stack                                         |
| Reconnection          | Session dies; resume on reconnect  | Sidecar stops CC session on disconnect. Workspace persists. Adapter reconnects with `resume: session_id` to continue conversation via CC's `--resume` |
| Protocol versioning   | `protocol_version` in init message | Cheap insurance for future protocol evolution                                  |
| Parsing layer         | Session parses, adapters forward raw | Adapters are pure transport. Sidecar becomes a dumb pipe. No re-serialization |
| CC message transport  | Raw NDJSON passthrough               | Sidecar forwards CLI stdout as-is over WebSocket. Zero parsing on sidecar     |

---

## Parsing Layer Refactor

Adapters are transport layers — they should not parse application-level messages. Currently `Adapter.Local` parses NDJSON lines into structs via `CLI.Parser`, then forwards parsed structs to Session. This creates a problem for the remote adapter: the sidecar would need to parse structs, re-serialize them to JSON, send over WebSocket, then the adapter would parse again.

**Solution:** Move parsing from adapters to Session. Adapters forward raw JSON (decoded maps or binary strings). Session parses once.

### Message Flow

```
Adapter.Local:
  Port stdout → JSON.decode (classify control vs CC) → if CC message:
    notify_raw_message(session, request_id, decoded_map)
    peek: if map["type"] == "result" → reset current_request

Adapter.Remote:
  WebSocket text frame (raw NDJSON line) →
    notify_raw_message(session, request_id, raw_binary)

Session:
  {:adapter_raw_message, ref, map_or_binary} →
    JSON.decode if binary → CLI.Parser.parse_message → struct
    if ResultMessage → mark request done (replaces notify_done)
    extract_session_id → dispatch to subscriber

Test Adapter (unchanged):
  notify_message(session, request_id, parsed_struct)
  notify_done(session, request_id, :completed)
```

### Adapter Notification API

```elixir
# Existing (kept for Test adapter backward compatibility):
notify_message(session, request_id, parsed_struct)
notify_done(session, request_id, :completed)
notify_error(session, request_id, reason)
notify_status(session, status)

# New (for Local and Remote adapters):
notify_raw_message(session, request_id, json_map_or_binary)
```

Session handles both `{:adapter_message, ...}` and `{:adapter_raw_message, ...}`.

### Sidecar Simplification

With raw passthrough, the sidecar becomes a dumb pipe:

- Spawns CC CLI via Port directly (uses `CLI.Command` for arg building, `CLI.Input` for stdin)
- Reads raw NDJSON lines from Port stdout
- Forwards each line as a WebSocket text frame (zero parsing, zero struct dependencies)
- Only understands protocol envelope messages (`init`, `query`, `stop`, `ready`, `done`, `error`)
- Does NOT import `ClaudeCode.Message`, `ClaudeCode.Content`, or `CLI.Parser`

---

## Component 1: `ClaudeCode.Adapter.Remote`

New adapter module in the `claude_code` package. Implements `ClaudeCode.Adapter` behaviour.

### Usage

```elixir
{:ok, session} = ClaudeCode.start_link(
  adapter: {ClaudeCode.Adapter.Remote,
    url: "wss://agent-runner.example.com/sessions",
    auth_token: "secret-token",
    workspace_id: "agent_abc123"
  },
  model: "sonnet",
  system_prompt: "You are a scraping agent.",
  max_turns: 20,
  hooks: %{
    PreToolUse: [%{matcher: "Bash", hooks: ["deny_if_rm_rf"]}],
    PostToolUse: [%{hooks: ["log_all"]}]
  },
  mcp_servers: %{"qultr" => %{command: "curl", args: [...]}}
)

# Everything after this is identical to local adapter
session
|> ClaudeCode.stream("Scrape events from example.com")
|> ClaudeCode.Stream.text_deltas()
|> Stream.each(&IO.write/1)
|> Stream.run()
```

### Adapter Config

| Option            | Type    | Required | Description                                                                                      |
| ----------------- | ------- | -------- | ------------------------------------------------------------------------------------------------ |
| `url`             | string  | yes      | WebSocket URL of the sidecar                                                                     |
| `auth_token`      | string  | yes      | Bearer token for authenticating to the sidecar                                                   |
| `workspace_id`    | string  | no       | Workspace directory name. Defaults to a generated ID. Reuse across runs for persistent workspace |
| `connect_timeout` | integer | no       | WebSocket connect timeout in ms (default: 10_000)                                                |
| `init_timeout`    | integer | no       | Time to wait for `ready` ack from sidecar (default: 30_000)                                      |

All other session options (model, system_prompt, hooks, mcp_servers, max_turns, etc.) are serialized in the WebSocket init message and passed through to the sidecar's local CC session.

### GenServer State

```elixir
%{
  session: pid(),              # parent Session GenServer
  conn: Mint.HTTP.t() | nil,   # Mint HTTP connection (for mint_web_socket)
  websocket: Mint.WebSocket.t() | nil,  # WebSocket state
  request_ref: reference(),    # Mint request reference
  request_id: reference(),     # current active request
  remote_session_id: String.t() | nil,  # session_id from ready ack (for resume)
  config: keyword()            # adapter config (url, auth_token, workspace_id)
}
```

### Lifecycle

```
init/1:
  1. notify_status(session, :provisioning)
  2. Mint.HTTP.connect(:https, host, port) + Mint.WebSocket.upgrade()
     Headers: [{"authorization", "Bearer #{auth_token}"}]
  3. Send init message: {protocol_version: 1, session_opts, workspace_id, resume: session_id?}
  4. Receive "ready" ack with session_id → store in state as remote_session_id
  5. notify_status(session, :ready)

send_query/4:
  1. Send query message: {request_id, prompt, opts}
  2. Receive messages → parse → notify_message(session, request_id, message)
  3. On ResultMessage → notify_done(session, request_id, :completed)

health/1:
  1. WebSocket ping/pong → :healthy
  2. No pong within timeout → :degraded
  3. Connection lost → {:unhealthy, :disconnected}

stop/1:
  1. Send "stop" message
  2. Close WebSocket
```

### Error Handling

- **Connection lost mid-session**: notify_error to Session. Session can retry or fail the run
- **Sidecar returns error**: parse error, notify_error
- **Init timeout** (sidecar not ready within configured timeout): fail with `{:error, :init_timeout}`

### Reconnection

When the WebSocket connection drops:

1. Sidecar stops the CC session (no grace period)
2. Workspace directory persists on disk
3. Adapter stores the `remote_session_id` from the original `ready` ack
4. On reconnect, adapter sends `init` with `resume: remote_session_id` and the same `workspace_id`
5. Sidecar starts a new CC session with `resume: session_id` in the same workspace
6. CC's `--resume` flag restores conversation history from its local session storage

This leverages CC's existing resume capability with no additional infrastructure.

---

## Component 2: `ClaudeCode.Sidecar`

A minimal Elixir application that runs on the agent runner server. Separate package (`claude_code_sidecar`) in the same repo, released independently to Hex.

### Responsibilities

1. Accept WebSocket connections from host applications
2. For each connection: start a local CC session, bridge messages
3. Manage workspace directories
4. Sandbox Bash execution via bubblewrap

### WebSocket Protocol

All messages are JSON objects with a `type` field. Same NDJSON format as the local adapter, wrapped in typed envelopes.

**Host → Sidecar:**

| Type        | Payload                         | When                                                                                                                                          |
| ----------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `init`      | `{protocol_version, session_opts, workspace_id, resume?}` | On connection. `protocol_version: 1`. Session opts: model, system_prompt, hooks, mcp_servers, max_turns, etc. Optional `resume: session_id` for reconnection. API key via env var on the runner, NOT in this message |
| `query`     | `{request_id, prompt, opts}`    | Start a new query                                                                                                                             |
| `control`   | `{request_id, subtype, params}` | Control request (model switch, etc.)                                                                                                          |
| `interrupt` | `{}`                            | Interrupt current query                                                                                                                       |
| `stop`      | `{}`                            | End session, clean up                                                                                                                         |

**Sidecar → Host:**

| Type               | Payload                       | When                                                      |
| ------------------ | ----------------------------- | --------------------------------------------------------- |
| `ready`            | `{session_id}`                | CC session initialized                                    |
| `message`          | `{request_id, message_json}`  | Each CC message (same JSON as local adapter NDJSON lines) |
| `done`             | `{request_id, reason}`        | Query complete                                            |
| `error`            | `{request_id, code, details}` | Error occurred                                            |
| `control_response` | `{request_id, response}`      | Response to control request                               |

### Session Management — Dumb Pipe

Each WebSocket connection = one CC CLI subprocess. The sidecar does NOT use `ClaudeCode.Session` or `ClaudeCode.Adapter.Local` — it spawns the CLI directly via Port and pipes raw NDJSON:

```elixir
# On "init" message:
workspace_path = Path.join(@workspaces_root, workspace_id)
File.mkdir_p!(workspace_path)

# Build CLI command using shared protocol modules
{executable, args} = ClaudeCode.CLI.Command.build(session_opts)
port = Port.open({:spawn_executable, "/bin/sh"}, [:binary, :exit_status, ...])

# Send ready ack
send_ws(conn, %{type: "ready", session_id: workspace_id})

# On "query" message:
json = ClaudeCode.CLI.Input.user_message(prompt, session_id)
Port.command(port, json <> "\n")

# Port stdout lines → WebSocket (raw passthrough, zero parsing):
# Each NDJSON line from CLI is forwarded as-is
send_ws(conn, %{type: "message", request_id: req_id, payload: raw_ndjson_line})

# Peek at line to detect result type (no struct parsing):
if String.contains?(line, "\"type\":\"result\"") ->
  send_ws(conn, %{type: "done", request_id: req_id, reason: "completed"})

# On WebSocket disconnect:
Port.close(port)
```

### Hooks

Hooks run **on the sidecar** (the remote server), not on the host. The hook config is serialized in the `init` message, and the sidecar's local CC session processes them with no round-trip back to the host.

This means:

- Elixir function hooks must be available on the sidecar
- For host-specific hooks, use webhook handlers that call back to the host over HTTP
- MCP-based hooks (in-process servers) work naturally since the CC session runs on the sidecar

### Workspace Management

```
/workspaces/
├── agent_abc123/        # persistent per agent
│   ├── .git/            # auto-managed
│   ├── scripts/         # agent-authored
│   ├── data/            # working data
│   └── ...
├── agent_def456/
│   └── ...
└── ...
```

- Workspace directory created on first use, persists across sessions
- Git initialized automatically. Snapshot before/after each session via hooks
- Workspace ID passed in the `init` message (typically the agent's xid)
- Old workspaces cleaned up by a periodic job or manual admin action

### Sandbox (Bubblewrap)

When CC's Bash tool executes a command, the sidecar wraps it in bubblewrap:

```bash
bwrap \
  --ro-bind / / \                          # read-only root
  --bind /workspaces/agent_abc/ /workspace \ # read-write workspace
  --unshare-net \                          # no network (unless allowed)
  --dev /dev \
  --proc /proc \
  -- bash -c "user_command_here"
```

This is configured via CC hooks — a `PreToolUse` hook on `Bash` that rewrites the command to run through bubblewrap. The hook config is injected by the sidecar based on the agent's allowed_domains.

For agents that need network access (scraping), selectively allow specific domains via bubblewrap network namespace + iptables rules.

### Authentication

The sidecar validates connections via a shared auth token:

- Token set as env var on the runner: `SIDECAR_AUTH_TOKEN`
- Host sends token in WebSocket handshake: `Authorization: Bearer <token>`
- Invalid token → connection rejected

### Configuration

The sidecar app has minimal config:

```elixir
config :claude_code_sidecar,
  port: 4040,
  workspaces_root: "/workspaces"
  # API key set via ANTHROPIC_API_KEY env var (NOT passed over WebSocket)
```

---

## Component 3: Deployment

The adapter is protocol-only — it doesn't manage deployment. The sidecar is deployed however the user prefers. Below are documented deployment options.

### Agent Runner Server Requirements

A Linux server with:

- Elixir runtime (for the sidecar app)
- Node.js runtime (for CC CLI)
- Git, Python, bubblewrap
- Disk space for workspaces
- TLS certificate for WSS

### Deployment Options

**Dokku** (recommended for qultr):

```bash
dokku apps:create agent-runner
dokku storage:mount agent-runner /var/lib/dokku/data/storage/workspaces:/workspaces
dokku config:set agent-runner \
  ANTHROPIC_API_KEY=sk-ant-... \
  SIDECAR_AUTH_TOKEN=secret \
  PORT=4040
git push dokku main
```

Other options:

- **systemd** service running a mix release
- **Docker compose** with a single long-running container

### Network

```
qultr-api (Server A)  ──WSS──▶  Agent Runner (Server B:4040)
                                      │
                                      ├──▶ Anthropic API (HTTPS)
                                      └──▶ qultr-api (Server A) for MCP tools
```

- Server B needs outbound HTTPS to `api.anthropic.com`
- Server B needs outbound HTTPS to Server A for MCP tool calls
- Server A needs outbound WSS to Server B:4040
- Server B exposes only port 4040 (sidecar WebSocket)

### MCP Tools in Remote Context

The CC session on the agent runner needs to call the host's MCP tools (e.g. qultr-api's docs, api, messages). Two options:

**Option A: HTTP MCP server (recommended for qultr)**

- Sidecar configures CC with an HTTP/SSE MCP server pointing to the host
- CC calls the MCP server over HTTP, authenticated via the agent's API key
- Requires the host to expose its MCP tools via HTTP (not just in-process)

**Option B: MCP config in init message**

- Host sends MCP server config in the init message
- Sidecar passes it through to CC's `mcp_servers` option
- Works for stdio-based MCP servers that can run on the agent runner

---

## Package Structure

Two packages in the same repo, released independently to Hex:

### `claude_code` (existing package)

New modules:

| Module                          | Description                                                          |
| ------------------------------- | -------------------------------------------------------------------- |
| `ClaudeCode.Adapter.Remote`     | WebSocket client adapter implementing `ClaudeCode.Adapter` behaviour |
| `ClaudeCode.Remote.Protocol`    | Shared message encoding/decoding for the WebSocket protocol          |

New dependency:

| Dep              | Purpose                                    |
| ---------------- | ------------------------------------------ |
| `mint_web_socket` | WebSocket client (built on Mint)          |

### `claude_code_sidecar` (new package, same repo)

Lives in `sidecar/` directory. Depends on `claude_code` only for `CLI.Command` (arg building), `CLI.Input` (stdin messages), and `Remote.Protocol` (envelope encoding). Does NOT depend on Session, Adapter, Parser, or any message/content structs.

| Module                                            | Description                                              |
| ------------------------------------------------- | -------------------------------------------------------- |
| `ClaudeCode.Sidecar`                               | Application entry point                                  |
| `ClaudeCode.Sidecar.SessionHandler`                | Per-connection WebSocket handler: Port ↔ WebSocket pipe  |
| `ClaudeCode.Sidecar.WorkspaceManager`              | Creates/manages workspace directories                    |

Dependencies:

| Dep           | Purpose                     |
| ------------- | --------------------------- |
| `claude_code` | CLI.Command, CLI.Input, Remote.Protocol only |
| `bandit`      | HTTP/WebSocket server       |
| `websock`     | WebSocket handler behaviour |

---

## What Changes in qultr-api

### Executor Changes

`RunWorker` / `Executor` passes the remote adapter config when the agent's runtime is `:remote`:

```elixir
case agent.config.runtime do
  :local ->
    # Current behavior: local CC session
    ClaudeCode.start_link(adapter: {ClaudeCode.Adapter.Local, []}, **session_opts)

  :remote ->
    ClaudeCode.start_link(
      adapter: {ClaudeCode.Adapter.Remote,
        url: Application.get_env(:qultr, :agent_runner_url),
        auth_token: Application.get_env(:qultr, :agent_runner_token),
        workspace_id: agent.xid
      },
      **session_opts
    )
end
```

### Agent.Config

Add `runtime` field:

```elixir
field :runtime, Ecto.Enum, values: [:local, :remote], default: :local
```

### App Config

```elixir
config :qultr,
  agent_runner_url: "wss://agent-runner.example.com/sessions",
  agent_runner_token: System.get_env("AGENT_RUNNER_TOKEN")
```

### MCP over HTTP

Expose the existing MCP tools via an HTTP endpoint so the remote CC sessions can call them. This may already be partially in place via the API dispatch system.
