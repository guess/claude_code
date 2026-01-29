# Remote Adapter Architecture for ClaudeCode Elixir SDK

## Overview

Create an adapter system that executes the Claude Code CLI on remote containers/sandboxes (Modal, E2B, Fly.io, etc.) while appearing to run locally. The SDK already has a clean adapter pattern that we extend.

## Current Architecture

The SDK has a well-designed adapter pattern:
- `ClaudeCode.Adapter` behaviour with 3 callbacks
- `ClaudeCode.Adapter.CLI` spawns local Port subprocess
- `ClaudeCode.Adapter.Test` provides mock testing
- Message protocol: `{:adapter_message, request_id, message}`, `{:adapter_done, request_id}`, `{:adapter_error, request_id, reason}`

## Proposed Module Structure

```
lib/claude_code/adapter/
  remote.ex                    # Main orchestrator (implements Adapter behaviour)
  remote/
    transport.ex               # Transport behaviour
    transport/
      websocket.ex             # WebSocket transport (primary)
      sse.ex                   # Server-Sent Events transport
      flame.ex                 # FLAME-based distributed Elixir
    backend.ex                 # Backend behaviour
    backend/
      modal.ex                 # Modal.com implementation
      e2b.ex                   # E2B.dev implementation
      fly.ex                   # Fly.io implementation
      custom.ex                # User-defined HTTP endpoint
    container.ex               # Container lifecycle manager
    pool.ex                    # Container pooling (for :pooled strategy)
    credential_proxy.ex        # Secure API key handling
```

## Core Components

### 1. Remote Adapter (`ClaudeCode.Adapter.Remote`)

Main orchestrator implementing `ClaudeCode.Adapter` behaviour:

```elixir
{:ok, session} = ClaudeCode.start_link(
  adapter: {ClaudeCode.Adapter.Remote, [
    backend: {ClaudeCode.Adapter.Remote.Backend.Modal, [
      token_id: System.get_env("MODAL_TOKEN_ID"),
      token_secret: System.get_env("MODAL_TOKEN_SECRET")
    ]},
    transport: :websocket,
    container_strategy: :pooled,  # :ephemeral | :pooled | :dedicated
    pool_size: 3,
    credential_mode: :proxy  # :proxy | :inject
  ]}
)
```

### 2. Transport Behaviour

Abstracts network communication:

```elixir
@callback connect(endpoint :: String.t(), opts :: keyword()) :: {:ok, state} | {:error, term()}
@callback send_input(state :: term(), data :: binary()) :: :ok | {:error, term()}
@callback subscribe(state :: term(), subscriber :: pid()) :: :ok
@callback disconnect(state :: term()) :: :ok
@callback alive?(state :: term()) :: boolean()
@callback reconnect(state :: term(), opts :: keyword()) :: {:ok, state} | {:error, term()}
```

### 3. Backend Behaviour

Abstracts container provisioning:

```elixir
@callback provision(spec :: container_spec(), opts :: keyword()) :: {:ok, container_info()} | {:error, term()}
@callback terminate(container_id()) :: :ok | {:error, term()}
@callback get_info(container_id()) :: {:ok, container_info()} | {:error, :not_found}
@callback available?() :: boolean()
@callback health_check(container_id()) :: :healthy | :unhealthy | {:error, term()}
```

### 4. Container Strategies

- **`:ephemeral`** - New container per session, terminated on session end
- **`:pooled`** - Reusable container pool, recycled between sessions
- **`:dedicated`** - Long-running container, persists across sessions

### 5. Credential Modes

- **`:proxy`** (recommended) - Container uses proxy URL, proxy injects API key
- **`:inject`** - API key passed to container at runtime via environment

#### Proxy Mode Details

In `:proxy` mode, the Elixir application runs an HTTP proxy that:
1. Container is configured with `ANTHROPIC_BASE_URL=http://proxy-host:port`
2. Container authenticates to proxy using a short-lived session token (passed via env)
3. Proxy validates session token and injects the real API key into outbound requests
4. API key never touches the container environment or logs

This prevents credential leakage if the container is compromised or logs are exposed.

## Dependencies

Add to `mix.exs`:

```elixir
{:websockex, "~> 0.5"},  # WebSocket client
{:jason, "~> 1.4"}       # Already present for JSON parsing
```

## Container Requirements

Remote containers must have:
1. Node.js 18+
2. Claude CLI installed (`npm install -g @anthropic-ai/claude-code`)
3. Transport server (WebSocket bridge to CLI stdin/stdout)
4. Network access to `api.anthropic.com`

## FLAME Alternative

For Elixir-native distribution, use FLAME transport:

```elixir
adapter: {ClaudeCode.Adapter.Remote, [
  transport: :flame,
  flame_pool: MyApp.ClaudePool,
  # Uses FLAME to spawn Adapter.CLI on remote BEAM nodes
]}
```

Benefits: Native Erlang distribution, no separate container image, shared app context.

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/claude_code/adapter/remote.ex` | Create | Main remote adapter GenServer |
| `lib/claude_code/adapter/remote/transport.ex` | Create | Transport behaviour |
| `lib/claude_code/adapter/remote/transport/websocket.ex` | Create | WebSocket implementation |
| `lib/claude_code/adapter/remote/backend.ex` | Create | Backend behaviour |
| `lib/claude_code/adapter/remote/backend/custom.ex` | Create | Custom HTTP endpoint backend |
| `lib/claude_code/adapter/remote/container.ex` | Create | Container lifecycle manager |
| `lib/claude_code/options.ex` | Modify | Add remote execution options |
| `docs/guides/remote-execution.md` | Create | Documentation |

## Implementation Phases

### Phase 1: Core Infrastructure
- `ClaudeCode.Adapter.Remote` - Main adapter
- `Transport` behaviour + WebSocket implementation (using `websockex`)
- `Backend` behaviour + Custom backend (user provides endpoint)
- Basic ephemeral container strategy
- Basic `:telemetry` events (connection, request, error)

### Phase 2: Production Features
- Container manager with pooling
- Credential proxy
- Error recovery and retry logic
- Health checks

### Phase 3: Provider Backends
- Modal.com backend
- E2B.dev backend
- Fly.io backend
- Container image + transport server

### Phase 4: Advanced Features
- FLAME transport
- Multi-region support
- Advanced metrics (histograms, pool utilization, container lifecycle)

## Verification

1. **Unit Tests**: Mock backend/transport for predictable testing
2. **Integration Tests**: Use `Backend.Test` that spawns local CLI
3. **E2E Tests**: Test against real Modal/E2B endpoints (CI secrets)
4. Run: `mix test test/claude_code/adapter/remote_test.exs`
5. Run: `mix quality` for full quality checks

## Decisions Made

- **Transport**: WebSocket (provider-agnostic, works with any backend)
- **WebSocket Library**: `websockex` ~> 0.5 (OTP behaviour-based, built-in reconnection, supervision tree friendly)
- **Backend Priority**: Custom endpoint first (user provides HTTP/WebSocket URL)
- **Transport Server**: Include in this repo under `priv/container/`

## Options Schema

Add to `ClaudeCode.Options`:

```elixir
remote: [
  type: :keyword_list,
  doc: "Remote execution options (used with Remote adapter)",
  keys: [
    endpoint: [
      type: :string,
      required: true,
      doc: "WebSocket endpoint URL (e.g., wss://my-container.example.com:8080)"
    ],
    connect_timeout: [
      type: :timeout,
      default: 30_000,
      doc: "Timeout for establishing WebSocket connection"
    ],
    request_timeout: [
      type: :timeout,
      default: 300_000,
      doc: "Timeout for individual requests (5 minutes default)"
    ],
    reconnect_attempts: [
      type: :non_neg_integer,
      default: 3,
      doc: "Number of reconnection attempts before failing"
    ],
    reconnect_interval: [
      type: :pos_integer,
      default: 1_000,
      doc: "Base interval between reconnection attempts (ms)"
    ],
    credential_mode: [
      type: {:in, [:proxy, :inject]},
      default: :inject,
      doc: "How API credentials are passed to container"
    ]
  ]
]
```

## Error Handling

Remote errors map to adapter protocol messages:

| Remote Error | Adapter Message |
|--------------|-----------------|
| Connection failed | `{:adapter_error, request_id, {:connection_failed, reason}}` |
| Connection lost mid-stream | `{:adapter_error, request_id, {:connection_lost, reason}}` |
| Container crashed | `{:adapter_error, request_id, {:container_crashed, exit_code}}` |
| Request timeout | `{:adapter_error, request_id, {:timeout, :request}}` |
| Reconnect exhausted | `{:adapter_error, request_id, {:reconnect_failed, attempts}}` |

In-flight requests during disconnection receive `{:adapter_error, request_id, {:connection_lost, reason}}` and must be retried by the caller.

## Telemetry Events

Phase 1 includes basic telemetry for observability:

```elixir
# Connection lifecycle
[:claude_code, :remote, :connect, :start]    # %{endpoint: url}
[:claude_code, :remote, :connect, :stop]     # %{endpoint: url}, %{duration: native_time}
[:claude_code, :remote, :connect, :exception] # %{endpoint: url}, %{reason: term}

# Reconnection
[:claude_code, :remote, :reconnect, :start]  # %{attempt: n, endpoint: url}
[:claude_code, :remote, :reconnect, :stop]   # %{attempt: n}, %{duration: native_time}

# Request/response
[:claude_code, :remote, :request, :start]    # %{request_id: ref}
[:claude_code, :remote, :request, :stop]     # %{request_id: ref}, %{duration: native_time}
[:claude_code, :remote, :request, :exception] # %{request_id: ref}, %{reason: term}
```

## WebSocket Transport Implementation

The WebSocket transport uses `websockex` behaviour pattern:

```elixir
defmodule ClaudeCode.Adapter.Remote.Transport.WebSocket do
  use WebSockex

  def start_link(endpoint, opts) do
    state = %{
      subscriber: Keyword.fetch!(opts, :subscriber),
      request_id: Keyword.fetch!(opts, :request_id),
      buffer: ""
    }
    WebSockex.start_link(endpoint, __MODULE__, state, opts)
  end

  @impl true
  def handle_frame({:text, data}, state) do
    # Buffer and parse newline-delimited JSON (same as CLI adapter)
    {messages, buffer} = parse_messages(state.buffer <> data)
    for msg <- messages do
      send(state.subscriber, {:adapter_message, state.request_id, msg})
    end
    {:ok, %{state | buffer: buffer}}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    # Attempt reconnection (websockex handles backoff)
    {:reconnect, state}
  end

  @impl true
  def terminate(reason, state) do
    send(state.subscriber, {:adapter_error, state.request_id, {:connection_closed, reason}})
    :ok
  end
end
```

## Refined Implementation Plan

### Phase 1: Core Remote Adapter (MVP)

**Files to create:**

1. `lib/claude_code/adapter/remote.ex`
   - Implements `ClaudeCode.Adapter` behaviour
   - Manages transport connection lifecycle
   - Buffers and parses JSON messages (like CLI adapter)

2. `lib/claude_code/adapter/remote/transport.ex`
   - Transport behaviour definition

3. `lib/claude_code/adapter/remote/transport/websocket.ex`
   - WebSocket client using `websockex` (OTP behaviour-based)
   - Implements `WebSockex` callbacks: `handle_frame/2`, `handle_disconnect/2`
   - Built-in reconnection via `{:reconnect, state}` return

4. `lib/claude_code/adapter/remote/backend.ex`
   - Backend behaviour definition

5. `lib/claude_code/adapter/remote/backend/custom.ex`
   - Accepts user-provided `endpoint` URL
   - No container provisioning (user manages their own)

6. `priv/container/transport-server/`
   - `package.json` - Node.js dependencies (ws)
   - `server.js` - WebSocket server that spawns Claude CLI
   - `Dockerfile` - Container image for easy deployment
   - `README.md` - Setup instructions

**Modify:**

7. `lib/claude_code/options.ex`
   - Add `:remote` option group with validation

**Create:**

8. `test/claude_code/adapter/remote_test.exs`
   - Unit tests with mock transport

9. `docs/guides/remote-execution.md`
   - Usage documentation

### Usage After Phase 1

```elixir
# User deploys transport server to their infrastructure
# Container runs: node server.js (exposes ws://host:8080)

{:ok, session} = ClaudeCode.start_link(
  adapter: {ClaudeCode.Adapter.Remote, [
    endpoint: "wss://my-container.example.com:8080",
    # API key passed securely to container via env var
  ]},
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Works exactly like local execution
result = ClaudeCode.query(session, "Hello from remote!")
```

### Future Phases

- **Phase 2**: Container lifecycle (ephemeral/pooled strategies)
- **Phase 3**: Provider-specific backends (Modal, E2B, Fly)
- **Phase 4**: FLAME transport for Elixir clusters
