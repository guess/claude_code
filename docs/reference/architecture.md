# Architecture

## Overview

The ClaudeCode Elixir SDK communicates with the Claude Code CLI (`claude` command) through a subprocess interface. The CLI handles all the complexity of communicating with Anthropic's API, while our SDK provides an idiomatic Elixir interface.

## How It Works

### 1. CLI Communication

The SDK spawns the `claude` command as a subprocess with bidirectional streaming:

```bash
(/bin/sh -c "(ANTHROPIC_API_KEY='...' claude --input-format stream-json --output-format stream-json --verbose)")
```

The CLI uses bidirectional streaming mode where:
- Queries are sent via stdin as JSON messages
- Responses come back via stdout as newline-delimited JSON

Key CLI flags we use:
- `--input-format stream-json`: Bidirectional streaming mode (reads queries from stdin)
- `--output-format stream-json`: Outputs JSON messages line by line
- `--verbose`: Includes all message types in output
- `--system-prompt`: Sets the system prompt
- `--allowed-tools`: Comma-separated list of allowed tools (e.g. "View,Bash(git:*)")
- `--model`: Specifies the model to use
- `--max-turns`: Limits conversation length
- `--cwd`: Sets working directory for file operations
- `--permission-mode`: Controls permission handling (default, acceptEdits, bypassPermissions)
- `--timeout`: Query timeout in milliseconds
- `--resume`: Resume a previous session by ID
- `--fork-session`: When resuming, create a new session ID instead of reusing the original

### 2. Message Flow

```
Elixir SDK <-> Persistent CLI subprocess <-> Anthropic API
     ^                   ^                          |
     |    stdin (query)  |                          v
     +--- stdout (JSON messages) ------------------+
```

The SDK maintains a persistent CLI subprocess with bidirectional I/O:
- Queries are written to stdin as JSON messages
- Responses come via stdout as newline-delimited JSON
- Three main message types in a typical response:
  - `system` (type: "system") - Initialization info with tools and session ID (on connect)
  - `assistant` (type: "assistant") - Streaming response chunks
  - `result` (type: "result") - Final complete response with metadata
- The SDK parses these and extracts the final response from the result message

### 3. Core Components

#### Session GenServer (`ClaudeCode.Session`)
```elixir
defmodule ClaudeCode.Session do
  use GenServer

  # State includes:
  # - adapter_module: The adapter module (e.g., ClaudeCode.Adapter.CLI)
  # - adapter_opts: Adapter-specific configuration
  # - adapter_pid: PID of the adapter process (started eagerly in init)
  # - requests: Map of request_ref => Request struct
  # - query_queue: Queue of pending queries (for serial execution)
  # - session_id: Claude session ID for conversation continuity
  # - session_options: Validated session-level options

  # Each Request tracks:
  # - id: Unique reference
  # - subscribers: Waiting callers
  # - messages: Buffered messages
  # - status: :active | :queued | :completed
end
```

#### Options Module (`ClaudeCode.Options`)
```elixir
defmodule ClaudeCode.Options do
  # Handles:
  # - NimbleOptions validation with helpful error messages
  # - Option precedence: query > session > app config > defaults
  # - Application config integration
  # - Type safety for all configuration options
end
```

The Session GenServer delegates communication to an adapter and uses a query queue for serial execution. This ensures efficient multi-turn conversations while maintaining conversation context.

#### Adapter Layer (`ClaudeCode.Adapter`)

The adapter layer provides a swappable backend interface. All adapters implement the `ClaudeCode.Adapter` behaviour:

```elixir
defmodule ClaudeCode.Adapter do
  # Callbacks:
  # - start_link/2: Provision the backend resource
  # - send_query/4: Send a prompt to Claude
  # - interrupt/1: Stop an in-progress query (sends SIGINT)
  # - health/1: Check backend health (:healthy | :degraded | {:unhealthy, reason})
  # - stop/1: Clean up resources
end
```

Adapters are specified as `{Module, config}` tuples:
```elixir
# Default CLI adapter (no config needed)
ClaudeCode.start_link(model: "opus")

# Explicit adapter config
ClaudeCode.start_link(adapter: {ClaudeCode.Adapter.CLI, cli_path: "/usr/bin/claude"})
```

The adapter communicates back to the session via messages:
- `{:adapter_message, request_id, message}` — parsed message
- `{:adapter_done, request_id, reason}` — query complete (`:completed` or `:interrupted`)
- `{:adapter_error, request_id, reason}` — error occurred

#### CLI Module (`ClaudeCode.CLI`)
```elixir
defmodule ClaudeCode.CLI do
  # Handles:
  # - Finding the claude binary
  # - Building command arguments from validated options
  # - Converting Elixir options to CLI flags
end
```

#### Message Parser (`ClaudeCode.Message`)
```elixir
defmodule ClaudeCode.Message do
  # Parses JSON lines into message structs:
  # - SystemMessage
  # - AssistantMessage
  # - UserMessage
  # - ResultMessage
  # - PartialAssistantMessage
end
```

## Configuration System (Phase 4)

### Options & Validation

The SDK uses a sophisticated configuration system with multiple layers of precedence:

```elixir
# Precedence: Query > Session > App Config > Defaults
final_options = Options.resolve_final_options(session_opts, query_opts)
```

#### Option Precedence Chain

1. **Query-level options** (highest precedence)
   ```elixir
   ClaudeCode.stream(session, "prompt", system_prompt: "Override for this query")
   ```

2. **Session-level options**
   ```elixir
   ClaudeCode.start_link(api_key: key, system_prompt: "Session default")
   ```

3. **Application config**
   ```elixir
   # config/config.exs
   config :claude_code,
     system_prompt: "App-wide default",
     timeout: 180_000
   ```

4. **Schema defaults** (lowest precedence)
   ```elixir
   @session_opts_schema [
     timeout: [type: :timeout, default: 300_000]
   ]
   ```

#### Flattened Options API

Options are passed directly as keyword arguments (no nested `:options` key):

```elixir
# Before (nested)
{:ok, session} = ClaudeCode.start_link(
  api_key: key,
  options: %{system_prompt: "...", timeout: 60_000}
)

# After (flattened)
{:ok, session} = ClaudeCode.start_link(
  api_key: key,
  system_prompt: "...",
  timeout: 60_000
)
```

#### NimbleOptions Integration

All options are validated using NimbleOptions for type safety:

```elixir
@session_opts_schema [
  api_key: [type: :string, required: true],
  model: [type: :string, default: "sonnet"],
  allowed_tools: [type: {:list, :string}],
]
```

Benefits:
- Helpful error messages for invalid options
- Auto-generated documentation
- Type safety at compile time
- Consistent validation across the API

#### CLI Flag Conversion

The Options module converts Elixir-style options to CLI flags:

```elixir
# Elixir options
[
  system_prompt: "You are helpful",
  allowed_tools: ["View", "Bash(git:*)"],
  max_turns: 20
]

# Converted to CLI flags
[
  "--system-prompt", "You are helpful",
  "--allowed-tools", "View,Bash(git:*)",
  "--permission-mode", "acceptEdits",
  "--max-turns", "20"
]
```

## Implementation Details

### Session Architecture

The Session GenServer uses a persistent CLI subprocess with serial query execution:

```elixir
# Each request gets a unique reference
defmodule Request do
  defstruct [
    :type,         # :sync | :async | :stream
    :caller_pid,   # PID for async/stream notifications
    :from,         # GenServer.reply target (sync only)
    :status        # :active | :completed
  ]
end
```

Key design decisions:
- **Eager Provisioning**: Adapter starts immediately in `init/1` — fast failure if backend can't start
- **Persistent Connection**: Single CLI subprocess for all queries
- **Query Queue**: Queries are executed serially to maintain conversation context
- **Session Continuity**: Session ID is captured and used for conversation context

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
def stream(session, prompt) do
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

The `:cli_path` option controls how the CLI binary is resolved:

- **`:bundled`** (default) — Uses `priv/bin/claude`. Auto-installs if missing. Verifies the installed version matches the SDK's pinned version and re-installs on mismatch.
- **`:global`** — Finds an existing system install via `System.find_executable/1` or common locations (`~/.npm-global/bin/claude`, `~/.claude/local/claude`, etc.). No auto-install.
- **`"/path/to/claude"`** — Uses that exact binary path.

Configure via application config or session option:
```elixir
config :claude_code, cli_path: :global
```

### Environment Variables

We'll pass through important environment variables:
- `ANTHROPIC_API_KEY`: For authentication
- `CLAUDE_CODE_ENTRYPOINT`: Set to "sdk-elixir" for telemetry

## Session Management

### Starting a Session

```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: "sk-ant-...",
  model: "opus",
  system_prompt: "You are an Elixir expert",
  allowed_tools: ["View", "Edit", "Bash(git:*)"],
  timeout: 120_000
)
```

This will:
1. Validate all options using NimbleOptions
2. Apply application config defaults
3. Start a GenServer with validated configuration
4. Eagerly start the adapter (which finds and prepares the CLI binary)
5. Return `{:error, reason}` if the adapter fails to start

Options are validated early to provide immediate feedback on configuration errors.

### Query Lifecycle

1. **Query starts**:
   - Validate query-level options using NimbleOptions
   - Merge session and query options (query takes precedence)
   - Generate unique request reference
   - Queue query if another is in progress, otherwise execute immediately
   - Delegate to adapter's `send_query/4`
   - Register request in `requests` map
2. **Stream messages**:
   - Parse JSON lines from stdout buffer
   - Route messages to current active request
   - Capture session ID from messages
3. **Query ends**:
   - Extract result from final message
   - Reply to caller or notify subscribers
   - Process next queued query if any
4. **Session continues**:
   - GenServer and CLI subprocess stay alive
   - Session ID enables conversation continuity

### Session Continuity

The SDK automatically maintains conversation context across queries within a session:

```elixir
# Start a session
{:ok, session} = ClaudeCode.start_link(api_key: key)

# First query establishes conversation context
session
|> ClaudeCode.stream("Hello, my name is Alice")
|> Stream.run()

# Subsequent queries automatically continue the conversation using stored session_id
session
|> ClaudeCode.stream("What's my name?")
|> ClaudeCode.Stream.text_content()
|> Enum.join()
# => "Your name is Alice!"

# Check current session ID
session_id = ClaudeCode.get_session_id(session)

# Clear session to start fresh conversation
:ok = ClaudeCode.clear(session)

# Fork a session to branch the conversation
{:ok, forked} = ClaudeCode.start_link(resume: session_id, fork_session: true)
```

**How it works:**
- Session IDs are captured from CLI responses and stored in the GenServer state
- The `--resume` flag is automatically added to subsequent queries
- Sessions maintain conversation history until explicitly cleared
- Use `fork_session: true` with `resume:` to create a branch with a new session ID

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

1. **Persistent Connection**: Single CLI subprocess avoids spawn overhead between queries
2. **Serial Execution**: Query queue ensures conversation context is maintained
3. **Eager Provisioning**: Adapter starts immediately — fast failure if backend is unavailable
4. **Lazy Streaming**: Use Elixir streams to avoid loading all messages in memory
5. **Interrupt Support**: Stop in-progress queries with `ClaudeCode.interrupt/1` to save tokens

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
