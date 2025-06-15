# ClaudeCode Elixir SDK Implementation Plan

## Recent Updates (December 2024)

- **Phase 3 Completed**: Added full streaming support
  - New `query/3` function returns Elixir Streams for real-time message processing
  - Created `ClaudeCode.Stream` module with utilities for text extraction, filtering, and buffering
  - Enhanced Session GenServer to handle concurrent streaming requests
  - Added `query_async/3` for manual message handling
  - Comprehensive test coverage for all streaming functionality

- **Phase 2 Completed**: Refactored message types to match official Claude Code SDK schema
  - Assistant/User messages now use nested structure with `message` field
  - Result messages use proper subtypes (`:error_max_turns`, `:error_during_execution`)
  - Content blocks use structs (`Content.Text`, `Content.ToolUse`, `Content.ToolResult`) instead of plain maps
  - Added `ClaudeCode.Types` module for centralized type definitions

## Overview

This document outlines the implementation strategy for the ClaudeCode Elixir SDK. The plan is structured to deliver value incrementally, starting with a minimal viable product (MVP) that provides core functionality, then building up to the full feature set described in the README.

## Guiding Principles

1. **Start Simple** - Get basic query/response working first
2. **Fail Fast** - Surface errors clearly from the beginning
3. **Test Early** - Build testing infrastructure alongside features
4. **Document as We Go** - Keep documentation current with implementation
5. **Real-World Usage** - Each phase should be usable in production

## Phase 1: MVP - Basic Query Interface (Week 1) ✅

**Goal**: Developers can start a session and query Claude synchronously

**Status**: COMPLETED

**Key Findings**:
- CLI requires shell wrapper with stdin redirect to prevent hanging
- CLI outputs three message types: system (init), assistant (streaming), result (final)
- Response content is in the result message's "result" field

### Core Components

```elixir
# lib/claude_code.ex
defmodule ClaudeCode do
  # Basic start_link/1 and query_sync/3
end

# lib/claude_code/session.ex
defmodule ClaudeCode.Session do
  use GenServer
  # Manages CLI subprocess
end

# lib/claude_code/cli.ex
defmodule ClaudeCode.CLI do
  # Handles CLI subprocess management
  # - Finding claude binary
  # - Building command arguments
  # - Port management
end

# lib/claude_code/message.ex
defmodule ClaudeCode.Message do
  # Basic message structs
end
```

### Features
- [x] Start a session with API key
- [x] Find and validate claude CLI binary
- [x] Send synchronous queries via subprocess
- [x] Parse JSON responses from stdout (system, assistant, result messages)
- [x] Basic error handling (CLI not found, auth errors)
- [x] Minimal options (model selection)

### Example Usage
```elixir
{:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")
{:ok, response} = ClaudeCode.query_sync(session, "Hello, Claude!")
IO.puts(response)
```

### Tests
- Session lifecycle (start/stop)
- Basic query/response
- Error cases (invalid API key, CLI missing)
- Shell command building with special characters
- Message parsing for all CLI output types

## Phase 2: Message Types & Content Blocks (Week 2) ✅

**Goal**: Properly parse and handle all message types from Claude

**Status**: COMPLETED

**Key Updates**:
- Refactored to match official SDK schema exactly
- Assistant and User messages now nest data under 'message' field
- Result subtypes standardized (error_max_turns, error_during_execution)
- Content blocks use proper structs instead of plain maps
- Added Types module for centralized type definitions

### New Components
```elixir
# lib/claude_code/types.ex - Type definitions matching SDK
# lib/claude_code/message/system.ex
# lib/claude_code/message/assistant.ex - Nested structure
# lib/claude_code/message/user.ex - Nested structure
# lib/claude_code/message/result.ex - Proper subtypes

# lib/claude_code/content/text.ex
# lib/claude_code/content/tool_use.ex
# lib/claude_code/content/tool_result.ex
```

### Features
- [x] Parse all message types with SDK-compliant schema
- [x] Handle content blocks within messages using structs
- [x] Pattern matching support for nested structures
- [x] Tool use detection
- [x] Type safety with proper Elixir typespecs

### Example Usage
```elixir
{:ok, messages} = ClaudeCode.query_sync(session, "Create a file")

Enum.each(messages, fn
  %ClaudeCode.AssistantMessage{content: blocks} ->
    # Handle assistant response
  %ClaudeCode.ToolUseMessage{tool: :write, args: args} ->
    # Handle tool usage
end)
```

## Phase 3: Streaming Support (Week 3) ✅

**Goal**: Enable efficient streaming of responses for real-time applications

**Status**: COMPLETED

### New Components
```elixir
# lib/claude_code/stream.ex
defmodule ClaudeCode.Stream do
  # Stream utilities for message processing
  # Uses Stream.resource/3 for proper lifecycle management
end
```

### Features
- [x] Streaming query interface with `query/3`
- [x] Lazy evaluation with native Elixir streams
- [x] Backpressure handling via process mailbox
- [x] Stream interruption and cleanup
- [x] Async queries with `query_async/3`
- [x] Real-time message processing

### Example Usage
```elixir
# Stream text content (recommended)
session
|> ClaudeCode.query("Generate a large module")
|> ClaudeCode.Stream.text_content()
|> Stream.each(&IO.write/1)
|> Stream.run()

# Work with raw messages
session
|> ClaudeCode.query("Complex task")
|> Stream.each(fn
  %Message.Assistant{message: %{content: content}} ->
    # Process assistant messages
  %Message.Result{result: result} ->
    # Handle final result
end)
|> Stream.run()
```

**Key Deliverables**:
- Added `query/3` and `query_async/3` functions to main module
- Created `ClaudeCode.Stream` module with utilities:
  - `text_content/1` - Extract text from assistant messages
  - `tool_uses/1` - Extract tool use blocks
  - `filter_type/2` - Filter by message type (:assistant, :result, :tool_use, etc.)
  - `until_result/1` - Take messages until result received
  - `buffered_text/1` - Buffer text until sentence boundaries
- Enhanced Session GenServer to support concurrent streaming requests
- Message delivery via process mailbox for async queries
- Proper stream cleanup with `cleanup_stream/1`
- Added 146 comprehensive tests including streaming integration tests
- Updated documentation with streaming examples and troubleshooting
- **Concurrent Query Fix**: Refactored Session to properly isolate concurrent requests with dedicated ports and buffers

## Phase 4: Options & Configuration (Week 4)

**Goal**: Support all configuration options from the SDK

### New Components
```elixir
# lib/claude_code/options.ex
defmodule ClaudeCode.Options do
  defstruct [
    :system_prompt,
    :allowed_tools,
    :max_conversation_turns,
    :working_directory,
    :permission_mode,
    :timeout
  ]
end
```

### Features
- [ ] Full options support
- [ ] Per-query option overrides
- [ ] Global configuration via Application env
- [ ] Option validation

### Example Usage
```elixir
options = %ClaudeCode.Options{
  system_prompt: "You are an Elixir expert",
  allowed_tools: [:read, :write],
  permission_mode: :auto_accept_reads
}

{:ok, session} = ClaudeCode.start_link(api_key: key, options: options)
```

## Phase 5: Permission System (Week 5)

**Goal**: Implement the permission handler behaviour and built-in modes

### New Components
```elixir
# lib/claude_code/permission_handler.ex
defmodule ClaudeCode.PermissionHandler do
  @callback handle_permission(tool :: atom(), args :: map(), context :: map()) ::
    :allow | {:deny, reason :: String.t()} | {:confirm, prompt :: String.t()}
end

# lib/claude_code/permission/default_handler.ex
# lib/claude_code/permission/modes.ex
```

### Features
- [x] Permission handler behaviour
- [x] Default permission handler
- [x] Built-in permission modes
- [x] Custom handler support

### Example Usage
```elixir
defmodule MyHandler do
  @behaviour ClaudeCode.PermissionHandler

  def handle_permission(:write, %{path: path}, _) do
    if path =~ ~r/\.env/, do: {:deny, "No env files"}, else: :allow
  end
end

{:ok, session} = ClaudeCode.start_link(
  api_key: key,
  permission_handler: MyHandler
)
```

## Phase 6: Error Handling & Recovery (Week 6)

**Goal**: Comprehensive error handling and automatic recovery

### New Components
```elixir
# lib/claude_code/error.ex
defmodule ClaudeCode.Error do
  defexception [:type, :message, :details]
end

# Specific error modules
# lib/claude_code/errors/cli_not_found_error.ex
# lib/claude_code/errors/cli_connection_error.ex
# lib/claude_code/errors/rate_limit_error.ex
```

### Features
- [x] Structured error types
- [x] Automatic retry logic
- [x] Rate limit handling
- [x] Connection recovery

## Phase 7: Telemetry Integration (Week 7)

**Goal**: Built-in observability for monitoring and debugging

### New Components
```elixir
# lib/claude_code/telemetry.ex
defmodule ClaudeCode.Telemetry do
  # Telemetry event definitions and helpers
end
```

### Features
- [x] Query start/stop/exception events
- [x] Tool usage events
- [x] Message received events
- [x] Performance metrics
- [x] Token usage tracking

### Example Usage
```elixir
:telemetry.attach(
  "log-claude",
  [:claude_code, :query, :stop],
  &MyApp.handle_telemetry/4,
  nil
)
```

## Phase 8: Supervision & Fault Tolerance (Week 8)

**Goal**: OTP supervision tree support for production systems

### New Components
```elixir
# lib/claude_code/supervisor.ex
defmodule ClaudeCode.Supervisor do
  use Supervisor
  # Supervision strategies
end

# lib/claude_code/registry.ex
defmodule ClaudeCode.Registry do
  # Named process registry
end
```

### Features
- [x] Supervisor support
- [x] Named sessions
- [x] Process registry
- [x] Automatic restart strategies
- [x] Session state recovery

## Phase 9: Advanced Features (Week 9-10)

**Goal**: Session resumption, connection pooling, and pipeline composition

### New Components
```elixir
# lib/claude_code/session/store.ex
# lib/claude_code/session/pool.ex
# lib/claude_code/pipeline.ex
```

### Features
- [x] Resume previous sessions (via --resume flag)
- [x] Session pooling for high concurrency
- [x] Pipeline composition helpers
- [x] Conversation management

## Phase 10: Testing & LiveView Support (Week 11)

**Goal**: Testing utilities and Phoenix LiveView integration

### New Components
```elixir
# lib/claude_code/test.ex
defmodule ClaudeCode.Test do
  # Mock sessions and helpers
end

# lib/claude_code/live_view.ex
defmodule ClaudeCode.LiveView do
  # LiveView-specific helpers
end
```

### Features
- [x] Mock session support
- [x] Test helpers
- [x] LiveView integration guide
- [x] Example LiveView components

## Phase 11: Documentation & Examples (Week 12)

**Goal**: Comprehensive documentation and real-world examples

### Deliverables
- [x] HexDocs with all modules documented
- [x] Example applications
  - CLI tool using ClaudeCode
  - Phoenix app with LiveView integration
  - Batch processing script
- [x] Performance tuning guide
- [x] Migration guide from Python SDK

## Phase 12: Polish & Release (Week 13)

**Goal**: Production-ready 1.0 release

### Tasks
- [x] Performance optimization
- [x] Memory leak testing
- [x] Load testing with concurrent sessions
- [x] Security audit (API key handling)
- [x] Hex.pm package preparation
- [x] GitHub CI/CD setup
- [x] Community feedback incorporation

## Testing Strategy

Each phase includes:
1. Unit tests for new modules
2. Integration tests with mock CLI
3. Property-based tests where applicable
4. Documentation tests (doctests)
5. Example code that serves as acceptance tests

## Release Strategy

### Alpha Releases (Phases 1-3)
- Basic functionality
- Breaking changes allowed
- Internal/beta testing

### Beta Releases (Phases 4-8)
- Feature complete for common use cases
- API stabilizing
- Community preview

### RC Releases (Phases 9-11)
- All features implemented
- API frozen
- Production testing

### 1.0 Release (Phase 12)
- Production ready
- Semantic versioning commitment
- Long-term support

## Risk Mitigation

### Technical Risks
1. **CLI compatibility** - Test across Claude Code CLI versions
2. **Performance** - Benchmark streaming with large responses
3. **Memory usage** - Monitor long-running sessions
4. **Concurrency** - Test high session counts

### Mitigation Strategies
- Maintain compatibility matrix with CLI versions
- Performance regression tests
- Memory profiling in CI
- Load testing suite
- Mock CLI for predictable testing

## Success Metrics

1. **Developer Experience**
   - Time to first successful query < 5 minutes
   - Clear error messages
   - Intuitive API

2. **Performance**
   - Streaming latency < 100ms
   - Memory usage stable over time
   - Support 100+ concurrent sessions

3. **Reliability**
   - 99.9% uptime for session management
   - Automatic recovery from crashes
   - No data loss during failures

4. **Adoption**
   - 100+ GitHub stars in first month
   - 10+ production users
   - Active community contributions

## Timeline Summary

- **Weeks 1-3**: Core functionality (MVP)
- **Weeks 4-6**: Full feature parity with Python SDK
- **Weeks 7-9**: Elixir-specific enhancements
- **Weeks 10-11**: Testing and integrations
- **Week 12**: Documentation and examples
- **Week 13**: Polish and release

Total: 3 months from start to 1.0 release

## Next Steps

1. Set up project structure and CI ✓
2. Implement Phase 1 MVP
3. Get early feedback from Elixir community
4. Iterate based on real usage
5. Continue through phases with regular alpha releases
