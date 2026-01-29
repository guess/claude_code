# Claude Code Transport Server

WebSocket server that bridges remote connections to the Claude CLI. This server is designed to run in a container and enable remote execution of Claude Code from an Elixir application.

## Quick Start

### Local Development

```bash
# Install dependencies
npm install

# Start the server
npm start

# Or with options
node server.js --port 3000 --host 127.0.0.1
```

### Docker

```bash
# Build the image
docker build -t claude-code-transport .

# Run with your API key
docker run -p 8080:8080 \
  -e ANTHROPIC_API_KEY=sk-ant-your-key-here \
  claude-code-transport
```

### Docker Compose

Create a `docker-compose.yml`:

```yaml
version: '3.8'
services:
  claude-transport:
    build: .
    ports:
      - "8080:8080"
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    restart: unless-stopped
```

Then run:

```bash
docker-compose up -d
```

## Configuration

### Command Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `--port` | 8080 | Port to listen on |
| `--host` | 0.0.0.0 | Host to bind to |
| `--claude` | claude | Path to claude binary |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 8080 | Server port |
| `HOST` | 0.0.0.0 | Server host |
| `CLAUDE_PATH` | claude | Path to claude binary |
| `ANTHROPIC_API_KEY` | (none) | API key for Claude (required) |

## Protocol

The server uses a simple WebSocket-based protocol:

### Connection

When a client connects, the server:
1. Spawns a new Claude CLI subprocess
2. Sends a connection acknowledgment: `{"type": "connected", "clientId": "..."}`

### Messages

- **Client → Server**: JSON messages are forwarded to CLI stdin
- **Server → Client**: CLI stdout lines are sent as WebSocket text frames

The CLI runs with `--input-format stream-json --output-format stream-json --verbose`, so all messages are newline-delimited JSON.

### Disconnection

When the WebSocket connection closes:
1. The CLI subprocess receives SIGTERM
2. If not terminated within 5 seconds, SIGKILL is sent
3. Resources are cleaned up

## Using with ClaudeCode Elixir SDK

```elixir
{:ok, session} = ClaudeCode.start_link(
  adapter: {ClaudeCode.Adapter.Remote, [
    endpoint: "ws://localhost:8080"
  ]},
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Works exactly like local execution
result = ClaudeCode.query(session, "Hello from remote!")
```

## Deployment

### Cloud Providers

The transport server can be deployed to any container platform:

- **Fly.io**: `fly launch --image your-registry/claude-code-transport`
- **Railway**: Connect your repo and deploy
- **Modal**: Use `modal.Image.from_dockerfile()`
- **AWS ECS/Fargate**: Push to ECR and create a service
- **Google Cloud Run**: Push to GCR and deploy

### Security Considerations

1. **API Key Management**: Use secrets management (e.g., Doppler, Vault) rather than environment variables in production
2. **Network Security**: Run behind a reverse proxy with TLS (wss://)
3. **Authentication**: Add authentication layer (JWT, API keys) before production use
4. **Resource Limits**: Set memory and CPU limits appropriate for your workload

### Production Checklist

- [ ] TLS termination (nginx, Caddy, cloud load balancer)
- [ ] Authentication middleware
- [ ] Rate limiting
- [ ] Health checks configured
- [ ] Logging and monitoring
- [ ] Auto-scaling rules
- [ ] Secrets management

## Troubleshooting

### Connection Refused

1. Check the server is running: `curl -v http://localhost:8080`
2. Verify port is not in use: `lsof -i :8080`
3. Check Docker port mapping: `docker ps`

### CLI Not Found

1. Verify Claude CLI is installed: `which claude`
2. Check PATH in container: `docker exec <container> which claude`
3. Use `--claude /full/path/to/claude` if needed

### Authentication Errors

1. Verify `ANTHROPIC_API_KEY` is set
2. Check key format (should start with `sk-ant-`)
3. Test key directly: `ANTHROPIC_API_KEY=... claude --help`

## License

MIT License - see the main ClaudeCode repository for details.
