# ClaudeCode Elixir SDK Architecture

## Overview

The ClaudeCode Elixir SDK communicates with the Claude Code CLI (`claude` command) through a subprocess interface. The CLI handles all the complexity of communicating with Anthropic's API, while our SDK provides an idiomatic Elixir interface.

## How It Works

### 1. CLI Communication

The SDK spawns the `claude` command as a subprocess using a shell wrapper to prevent hanging:

```bash
(/bin/sh -c "(ANTHROPIC_API_KEY='...' claude --output-format stream-json --verbose --print 'your prompt here'
) </dev/null")
```

This approach ensures proper TTY handling and prevents the CLI from buffering output.

Key CLI flags we'll use:
- `--output-format stream-json`: Outputs JSON messages line by line
- `--verbose`: Includes all message types in output
- `--print`: Non-interactive mode, exits after completion
- `--system-prompt`: Sets the system prompt
- `--allowed-tools`: Comma-separated list of allowed tools
- `--model`: Specifies the model to use
- `--resume`: Resume a previous session by ID
- `--continue`: Continue the most recent conversation

### 2. Message Flow

```
Elixir SDK -> Spawns CLI subprocess -> CLI talks to Anthropic API
     ^                                           |
     |                                           v
     +------ JSON messages over stdout ----------+
```

The CLI outputs newline-delimited JSON messages to stdout:
- Each line is a complete JSON object
- Three main message types in a typical query:
  - `system` (type: "system") - Initialization info with tools and session ID
  - `assistant` (type: "assistant") - Streaming response chunks
  - `result` (type: "result") - Final complete response with metadata
- The SDK parses these and extracts the final response from the result message

### 3. Core Components

#### Session GenServer (`ClaudeCode.Session`)
```elixir
defmodule ClaudeCode.Session do
  use GenServer
  
  # State includes:
  # - active_requests: Map of request_id => RequestInfo
  # - api_key: Authentication key
  # - model: Model to use for queries
  
  # Each RequestInfo tracks:
  # - port: Dedicated CLI subprocess
  # - buffer: Request-specific JSON buffer
  # - type: :sync or :stream
  # - subscribers: PIDs receiving stream messages
  # - messages: Accumulated messages
end
```

The Session GenServer supports multiple concurrent queries, with each query spawning its own CLI subprocess. This design ensures true concurrency without race conditions.

#### CLI Module (`ClaudeCode.CLI`)
```elixir
defmodule ClaudeCode.CLI do
  # Handles:
  # - Finding the claude binary
  # - Building command arguments
  # - Spawning the process
  # - Managing stdin/stdout/stderr
end
```

#### Message Parser (`ClaudeCode.Parser`)
```elixir
defmodule ClaudeCode.Parser do
  # Parses JSON lines into message structs:
  # - AssistantMessage
  # - ToolUseMessage
  # - ResultMessage
  # - etc.
end
```

## Implementation Details

### Concurrent Query Support

The Session GenServer is designed to handle multiple concurrent queries efficiently:

```elixir
# Each request gets a unique ID and dedicated resources
defmodule RequestInfo do
  defstruct [
    :id,           # Unique request reference
    :type,         # :sync | :stream
    :port,         # Dedicated CLI subprocess
    :buffer,       # Request-specific JSON buffer
    :from,         # GenServer.reply target (sync only)
    :subscribers,  # PIDs receiving messages (stream only)
    :messages,     # Accumulated messages
    :status,       # :active | :completed
    :created_at    # For timeout tracking
  ]
end
```

Key design decisions:
- **Port Isolation**: Each request owns its CLI subprocess
- **Message Routing**: Port messages are routed by looking up the port in active requests
- **Buffer Isolation**: Each request has its own JSON parsing buffer
- **Cleanup**: Requests are automatically cleaned up on completion or timeout

### Process Management

We'll use Elixir's `Port` for subprocess management:

```elixir
port = Port.open({:spawn_executable, cli_path}, [
  :binary,
  :exit_status,
  :stderr_to_stdout,
  :stream,
  :hide,
  args: build_args(options)
])
```

### Streaming

For streaming responses, we'll use Elixir's `Stream` module:

```elixir
def query(session, prompt) do
  Stream.resource(
    fn -> start_query(session, prompt) end,
    fn state -> receive_next_message(state) end,
    fn state -> cleanup(state) end
  )
end
```

### Error Handling

The CLI can fail in several ways:
1. **CLI not found**: Check common locations, provide installation instructions
2. **Auth errors**: CLI will output error JSON
3. **Process crashes**: Monitor subprocess, restart if needed
4. **Rate limits**: Parse error messages, implement backoff

### JSON Message Format

Messages from the CLI look like:

```json
{"type": "message", "role": "assistant", "content": [{"type": "text", "text": "Hello!"}]}
{"type": "tool_use", "id": "123", "name": "read_file", "input": {"path": "file.ex"}}
{"type": "result", "tool_use_id": "123", "output": "file contents..."}
```

## Environment Setup

### Finding the CLI

The SDK will search for `claude` in:
1. System PATH (via `System.find_executable/1`)
2. Common npm global locations:
   - `~/.npm-global/bin/claude`
   - `/usr/local/bin/claude`
   - `~/.local/bin/claude`
3. Local node_modules:
   - `./node_modules/.bin/claude`
   - `~/node_modules/.bin/claude`

### Environment Variables

We'll pass through important environment variables:
- `ANTHROPIC_API_KEY`: For authentication
- `CLAUDE_CODE_ENTRYPOINT`: Set to "sdk-elixir" for telemetry

## Session Management

### Starting a Session

```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: "sk-ant-...",
  model: "claude-3-5-sonnet-20241022"
)
```

This will:
1. Start a GenServer
2. Find the CLI binary
3. Prepare command arguments
4. Ready for queries (no subprocess yet)

### Query Lifecycle

1. **Query starts**: 
   - Generate unique request ID
   - Spawn dedicated CLI subprocess with prompt
   - Register request in `active_requests` map
2. **Stream messages**: 
   - Route port messages to correct request via port lookup
   - Parse JSON lines with request-specific buffer
   - Send messages only to request's subscribers
3. **Query ends**: 
   - Extract result from final message
   - CLI process exits, cleanup port
   - Remove request from `active_requests`
4. **Session continues**: 
   - GenServer stays alive for next query
   - Multiple queries can run concurrently

### Resuming Sessions

The CLI supports resuming previous conversations:

```elixir
# Resume by session ID
{:ok, session} = ClaudeCode.resume("session-123", api_key: key)

# Continue most recent
{:ok, session} = ClaudeCode.continue(api_key: key)
```

## Permissions

The CLI has built-in permission handling, but we'll add an Elixir layer:

```elixir
defmodule MyHandler do
  @behaviour ClaudeCode.PermissionHandler
  
  def handle_permission(tool, args, context) do
    # Called when CLI would ask for permission
    # Return :allow, {:deny, reason}, or {:confirm, prompt}
  end
end
```

## Testing Strategy

### Unit Tests
- Mock the Port for predictable message sequences
- Test message parsing with fixture JSON
- Test error handling scenarios

### Integration Tests
- Use a mock CLI script for full flow testing
- Test real CLI if available (behind feature flag)

### Example Mock CLI

```bash
#!/usr/bin/env bash
# test/fixtures/mock_claude

echo '{"type": "message", "role": "assistant", "content": [{"type": "text", "text": "Mock response"}]}'
echo '{"type": "done"}'
```

## Performance Considerations

1. **Concurrent Queries**: Each Session can handle multiple concurrent queries
2. **Request Isolation**: Each query has its own port and buffer - no contention
3. **Message Routing**: O(1) port-to-request lookup for efficient message delivery
4. **Automatic Cleanup**: Requests timeout after 5 minutes to prevent resource leaks
5. **Lazy Streaming**: Use Elixir streams to avoid loading all messages in memory

## Security

1. **API Key Handling**: Never log or expose API keys
2. **Command Injection**: Use `Port.open` with explicit args list (no shell)
3. **File Access**: Respect CLI's built-in file access controls
4. **Process Isolation**: Each session runs in its own subprocess

## Future Enhancements

1. **Native Elixir Implementation**: Eventually bypass CLI for direct API calls
2. **WebSocket Support**: If CLI adds WebSocket mode
3. **Distributed Sessions**: Store session state in distributed cache
4. **Hot Code Reloading**: Update SDK without dropping sessions