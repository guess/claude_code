# Remote Execution

This guide explains how to run Claude Code on remote containers using the Remote Adapter. This enables sandboxed execution, horizontal scaling, and execution in cloud environments.

## Overview

The Remote Adapter connects to a container (Modal, E2B, Fly.io, or custom) via WebSocket and communicates with the Claude CLI running there. From your application's perspective, it works identically to local execution.

```
┌─────────────────┐     WebSocket      ┌─────────────────────────────────┐
│   Elixir SDK    │◄──────────────────►│     Remote Container            │
│                 │                    │  ┌───────────────────────────┐  │
│  Remote Adapter │                    │  │   Transport Server        │  │
│                 │                    │  │  (WebSocket → stdin/out)  │  │
└─────────────────┘                    │  └───────────────────────────┘  │
                                       │           ▲     │               │
                                       │           │     ▼               │
                                       │  ┌───────────────────────────┐  │
                                       │  │      Claude CLI           │  │
                                       │  │  (claude --stream-json)   │  │
                                       │  └───────────────────────────┘  │
                                       └─────────────────────────────────┘
```

## Quick Start

### 1. Deploy the Transport Server

First, deploy the transport server to your container platform. The SDK includes a reference implementation in `priv/container/transport-server/`.

```bash
# Using Docker
cd priv/container/transport-server
docker build -t claude-code-transport .
docker run -p 8080:8080 -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY claude-code-transport
```

### 2. Connect from Elixir

```elixir
# Add to your deps
{:claude_code, "~> 0.16"},
{:websockex, "~> 0.5"}

# Start a remote session
{:ok, session} = ClaudeCode.start_link(
  adapter: {ClaudeCode.Adapter.Remote, []},
  endpoint: "wss://my-container.example.com:8080",
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Works exactly like local execution
result = ClaudeCode.query(session, "Hello from remote!")
IO.puts(result)
```

## Configuration Options

### Session Options

```elixir
ClaudeCode.start_link(
  # Required: Use the remote adapter
  adapter: {ClaudeCode.Adapter.Remote, []},

  # Required: WebSocket endpoint
  endpoint: "wss://my-container.example.com:8080",

  # Or use the nested remote options format
  remote: [
    endpoint: "wss://my-container.example.com:8080",
    connect_timeout: 30_000,      # Connection timeout (default: 30s)
    request_timeout: 300_000,     # Request timeout (default: 5 min)
    reconnect_attempts: 3,        # Max reconnection attempts
    reconnect_interval: 1_000,    # Base reconnect interval (ms)
    credential_mode: :inject      # How API key is passed
  ],

  # Standard ClaudeCode options work as expected
  api_key: "sk-ant-...",
  model: "sonnet",
  system_prompt: "You are a helpful assistant"
)
```

### Credential Modes

| Mode | Description |
|------|-------------|
| `:inject` | API key passed to container via environment variable (default) |
| `:proxy` | Container uses proxy URL that injects API key (more secure, Phase 2) |

## Container Setup

### Requirements

Your container must have:

1. **Node.js 18+** - Runtime for Claude CLI
2. **Claude CLI** - `npm install -g @anthropic-ai/claude-code`
3. **Transport server** - WebSocket bridge (included in this SDK)
4. **Network access** - Must reach `api.anthropic.com`

### Using the Reference Transport Server

The SDK includes a production-ready transport server:

```bash
# Install dependencies
cd priv/container/transport-server
npm install

# Run locally
ANTHROPIC_API_KEY=sk-ant-... node server.js

# Or with options
node server.js --port 3000 --host 127.0.0.1
```

### Docker Deployment

```dockerfile
# Use the included Dockerfile
FROM node:20-slim
RUN npm install -g @anthropic-ai/claude-code
WORKDIR /app
COPY package.json server.js ./
RUN npm install --production
EXPOSE 8080
CMD ["node", "server.js"]
```

## Cloud Deployments

### Fly.io

```bash
# Deploy transport server
cd priv/container/transport-server
fly launch --name claude-transport

# Set API key secret
fly secrets set ANTHROPIC_API_KEY=sk-ant-...

# Connect from Elixir
endpoint: "wss://claude-transport.fly.dev"
```

### Railway

1. Connect your repo to Railway
2. Set `ANTHROPIC_API_KEY` environment variable
3. Deploy from `priv/container/transport-server/`
4. Use the assigned domain as endpoint

### Modal (Phase 3)

```elixir
# Coming in Phase 3
{:ok, session} = ClaudeCode.start_link(
  adapter: {ClaudeCode.Adapter.Remote, [
    backend: ClaudeCode.Adapter.Remote.Backend.Modal,
    backend_opts: [
      token_id: System.get_env("MODAL_TOKEN_ID"),
      token_secret: System.get_env("MODAL_TOKEN_SECRET")
    ]
  ]}
)
```

## Error Handling

The Remote Adapter maps errors to the standard adapter protocol:

```elixir
case ClaudeCode.query(session, "Hello") do
  {:ok, result} ->
    IO.puts(result)

  {:error, {:connection_failed, reason}} ->
    Logger.error("Failed to connect: #{inspect(reason)}")

  {:error, {:connection_lost, reason}} ->
    Logger.error("Connection lost mid-stream: #{inspect(reason)}")

  {:error, {:timeout, :request}} ->
    Logger.error("Request timed out")

  {:error, {:reconnect_failed, attempts}} ->
    Logger.error("Reconnection failed after #{attempts} attempts")

  {:error, reason} ->
    Logger.error("Unknown error: #{inspect(reason)}")
end
```

### Automatic Reconnection

The transport automatically attempts reconnection on disconnection:

```elixir
remote: [
  reconnect_attempts: 3,      # Number of retries
  reconnect_interval: 1_000   # Base interval (exponential backoff)
]
```

## Telemetry

The Remote Adapter emits telemetry events for observability:

```elixir
# Attach handlers in your application
:telemetry.attach_many(
  "claude-code-remote",
  [
    [:claude_code, :remote, :connect, :start],
    [:claude_code, :remote, :connect, :stop],
    [:claude_code, :remote, :connect, :exception],
    [:claude_code, :remote, :reconnect, :start],
    [:claude_code, :remote, :reconnect, :stop],
    [:claude_code, :remote, :request, :start],
    [:claude_code, :remote, :request, :stop],
    [:claude_code, :remote, :request, :exception]
  ],
  &MyApp.Telemetry.handle_event/4
)
```

### Event Metadata

| Event | Metadata |
|-------|----------|
| `connect:start` | `%{endpoint: url}` |
| `connect:stop` | `%{endpoint: url}`, measurements: `%{duration: native_time}` |
| `connect:exception` | `%{endpoint: url, reason: term}` |
| `request:start` | `%{request_id: ref}` |
| `request:stop` | `%{request_id: ref}`, measurements: `%{duration: native_time}` |

## Security Considerations

### API Key Management

1. **Never hardcode API keys** - Use environment variables or secrets management
2. **Use `:proxy` mode in production** (Phase 2) - Keeps API key on your infrastructure
3. **Rotate keys regularly** - Especially for long-running containers

### Network Security

1. **Always use TLS** - Use `wss://` endpoints, never `ws://` in production
2. **Add authentication** - Implement JWT or API key validation at the transport layer
3. **Limit network access** - Container should only reach Anthropic's API

### Container Isolation

1. **Use read-only filesystems** where possible
2. **Limit container resources** - Set CPU/memory limits
3. **Run as non-root** - The included Dockerfile creates a `claude` user

## Troubleshooting

### Connection Refused

```elixir
{:error, {:connection_failed, :econnrefused}}
```

1. Verify the container is running
2. Check the endpoint URL is correct
3. Verify port is exposed: `docker ps` or cloud platform dashboard
4. Test with: `websocat wss://your-endpoint:8080`

### Authentication Errors

```elixir
# Result message with is_error: true
%ClaudeCode.Message.ResultMessage{is_error: true, errors: ["Authentication failed"]}
```

1. Verify `ANTHROPIC_API_KEY` is set in the container
2. Check key format (should start with `sk-ant-`)
3. Verify key has sufficient permissions

### Timeout Errors

```elixir
{:error, {:timeout, :request}}
```

1. Increase `request_timeout` for long-running queries
2. Check container resources (may be CPU/memory constrained)
3. Verify network connectivity between SDK and container

### Reconnection Failures

```elixir
{:error, {:reconnect_failed, 3}}
```

1. Container may have crashed - check container logs
2. Network issues - verify connectivity
3. Increase `reconnect_attempts` if transient issues are common

## Example: Phoenix LiveView Integration

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, session} = ClaudeCode.start_link(
      adapter: {ClaudeCode.Adapter.Remote, []},
      endpoint: Application.get_env(:my_app, :claude_endpoint),
      api_key: Application.get_env(:my_app, :anthropic_api_key)
    )

    {:ok, assign(socket, session: session, messages: [])}
  end

  def handle_event("send", %{"message" => message}, socket) do
    # Stream responses to the user
    socket.assigns.session
    |> ClaudeCode.stream(message)
    |> Stream.each(fn msg ->
      send(self(), {:claude_message, msg})
    end)
    |> Stream.run()

    {:noreply, socket}
  end

  def handle_info({:claude_message, %ClaudeCode.Message.ResultMessage{} = msg}, socket) do
    {:noreply, update(socket, :messages, &[msg.result | &1])}
  end

  def handle_info({:claude_message, _}, socket) do
    {:noreply, socket}
  end
end
```

## Roadmap

### Phase 1 (Current)
- ✅ WebSocket transport
- ✅ Custom backend (user-provided endpoint)
- ✅ Basic telemetry
- ✅ Automatic reconnection

### Phase 2 (Planned)
- Container pooling (`:pooled` strategy)
- Credential proxy mode
- Health checks
- Advanced retry logic

### Phase 3 (Planned)
- Modal.com backend
- E2B.dev backend
- Fly.io backend

### Phase 4 (Planned)
- FLAME transport (native Erlang distribution)
- Multi-region support
- Advanced metrics
