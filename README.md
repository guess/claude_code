# ClaudeCode

An Elixir SDK for Claude Code - bringing AI-powered coding assistance to the Elixir ecosystem.

> **Status**: Alpha (Phase 4 Complete) - Full options & configuration support is now available! Flattened options API with NimbleOptions validation, option precedence, and application config support. See our [Roadmap](docs/ROADMAP.md) for implementation timeline.

## Project Overview

ClaudeCode is an idiomatic Elixir interface to the Claude Code CLI, designed to leverage Elixir's strengths in building concurrent, fault-tolerant applications. The SDK provides a GenServer-based API for managing Claude sessions, with built-in support for streaming, supervision, and Phoenix LiveView integration.

## Documentation

- 📋 **[Roadmap](docs/ROADMAP.md)** - Implementation plan and timeline
- 🔮 **[Vision](docs/VISION.md)** - Complete API documentation and future features
- 🏗️ **[Architecture](docs/ARCHITECTURE.md)** - Technical design decisions
- 🛠️ **[Development Setup](docs/DEV_SETUP.md)** - Developer environment guide

## Current Status

✅ **Phase 4 is complete!** The SDK now provides:

- **NEW: Flattened options API** - Pass options directly as keyword arguments 
- **NEW: NimbleOptions validation** - Type safety with helpful error messages
- **NEW: Option precedence system** - Query > Session > App Config > Defaults
- **NEW: Application configuration support** - Set defaults in config files
- **NEW: Query-level option overrides** - Override session options per query
- Streaming support with native Elixir Streams
- Real-time message processing with stream utilities
- Async query support with message delivery
- Full message type parsing (System, Assistant, User, Result) matching official SDK schema
- Content block handling (Text, ToolUse, ToolResult) with proper struct types
- Nested message structure for Assistant/User messages as per SDK spec
- Pattern matching support for all message types
- Error handling with proper Result subtypes (error_max_turns, error_during_execution)
- Comprehensive test suite with 199 passing tests including options validation

```
claude_code/
├── lib/
│   ├── claude_code.ex         # Main API module with flattened options support
│   └── claude_code/
│       ├── session.ex         # GenServer with options validation
│       ├── options.ex         # Options validation & CLI conversion (NEW)
│       ├── stream.ex          # Stream utilities
│       ├── cli.ex            # CLI binary handling with options support
│       ├── message.ex        # Unified message parsing
│       ├── content.ex        # Content block parsing
│       ├── types.ex          # Type definitions matching SDK schema
│       ├── message/
│       │   ├── system.ex     # System message type
│       │   ├── assistant.ex  # Assistant message type (nested structure)
│       │   ├── user.ex       # User message type (nested structure)
│       │   └── result.ex     # Result message type with proper subtypes
│       └── content/
│           ├── text.ex       # Text content blocks
│           ├── tool_use.ex   # Tool use blocks
│           └── tool_result.ex # Tool result blocks
├── test/
│   ├── claude_code_test.exs       # Updated with flattened options tests
│   └── claude_code/
│       ├── session_test.exs
│       ├── options_test.exs           # Options module tests (NEW)
│       ├── option_precedence_test.exs # Option precedence tests (NEW)
│       ├── stream_test.exs            # Stream module tests
│       ├── cli_test.exs               # Updated for new CLI interface
│       ├── message_test.exs
│       ├── content_test.exs
│       ├── integration_test.exs
│       ├── integration_stream_test.exs # Streaming integration tests
│       └── (matching test structure)
└── docs/                      # Project documentation
```

## Prerequisites

Before using this SDK, you need to have the Claude Code CLI installed:

1. **Install Claude Code CLI**:
   - Visit [claude.ai/code](https://claude.ai/code)
   - Follow the installation instructions for your platform
   - Verify installation: `claude --version`

2. **Get an API Key**:
   - Sign up at [console.anthropic.com](https://console.anthropic.com)
   - Create an API key
   - Keep it secure!

## Installation

> **Note**: This package is not yet published to Hex.pm

For now, you can use it directly from GitHub:

```elixir
# In your mix.exs
def deps do
  [
    {:claude_code, github: "guess/claude_code", branch: "main"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Quick Start

### Basic Usage

```elixir
# Start a Claude session with basic options
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Start with advanced configuration (NEW in Phase 4!)
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "opus",
  system_prompt: "You are an Elixir expert",
  allowed_tools: ["View", "GlobTool", "Bash(git:*)"],
  max_conversation_turns: 20,
  permission_mode: :auto_accept_reads,
  timeout: 120_000
)

# Send a query and get a response
{:ok, response} = ClaudeCode.query_sync(session, "Hello, Claude!")
IO.puts(response)
# => "Hello! How can I assist you today?"

# Override options per query (NEW!)
{:ok, response} = ClaudeCode.query_sync(session, "Optimize this code",
  system_prompt: "Focus on performance optimization",
  timeout: 180_000
)

# Check if session is alive
ClaudeCode.alive?(session)
# => true

# Stop the session when done
ClaudeCode.stop(session)
```

### Application Configuration (NEW in Phase 4!)

```elixir
# Set defaults in your config files
# config/config.exs
config :claude_code,
  model: "opus",
  timeout: 180_000,
  permission_mode: :auto_accept_reads,
  system_prompt: "You are a helpful Elixir assistant"

# Sessions now automatically use these defaults
{:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")
# Uses the configured defaults ↑
```

### Streaming Responses with Option Overrides

```elixir
# Stream all messages as they arrive
session
|> ClaudeCode.query("Write a story about Elixir")
|> Enum.each(&IO.inspect/1)

# Stream with query-level option overrides (NEW!)
session
|> ClaudeCode.query("Explain pattern matching",
     system_prompt: "Focus on practical examples",
     allowed_tools: ["View"])
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# React to tool usage in real-time
session
|> ClaudeCode.query("Create a new elixir module named Tester")
|> ClaudeCode.Stream.tool_uses()
|> Enum.each(fn tool_use ->
  IO.puts("Claude is using: #{tool_use.name}")
end)

# Buffer text until complete sentences
session
|> ClaudeCode.query("Tell me about GenServers")
|> ClaudeCode.Stream.buffered_text()
|> Enum.each(&IO.puts/1)

# Filter specific message types
session
|> ClaudeCode.query("Help me debug this code")
|> ClaudeCode.Stream.filter_type(:assistant)
|> Enum.map(& &1.message.content)

# Async queries with manual message handling
{:ok, request_id} = ClaudeCode.query_async(session, "Complex task",
  timeout: 300_000  # Override timeout for this query
)

receive do
  {:claude_message, ^request_id, message} ->
    IO.inspect(message)
  {:claude_stream_end, ^request_id} ->
    IO.puts("Stream complete!")
end
```

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/guess/claude_code.git
   cd claude_code
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Run tests:
   ```bash
   mix test
   ```

4. Run quality checks:
   ```bash
   mix quality  # Runs format check, credo, and dialyzer
   ```

## Contributing

We welcome contributions! The project is in its early stages, making it a great time to get involved and help shape the SDK.

### Getting Started

1. Check the [Roadmap](docs/ROADMAP.md) for current development phase
2. Pick an unimplemented feature from the current or next phase
3. Open an issue to discuss your approach
4. Submit a PR with tests and documentation

### Development Guidelines

- Follow Elixir style conventions
- Write tests for all new functionality
- Update documentation as you go
- Keep PRs focused and atomic

## API Documentation

### Starting a Session (Updated for Phase 4!)

```elixir
# Basic usage
{:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

# With flattened configuration options
{:ok, session} = ClaudeCode.start_link(
  api_key: "sk-ant-...",
  model: "opus",
  system_prompt: "You are an Elixir expert",
  allowed_tools: ["View", "GlobTool", "Bash(git:*)"],
  max_conversation_turns: 50,
  working_directory: "/my/project",
  permission_mode: :auto_accept_reads,
  timeout: 120_000
)

# Named session for easier reference
{:ok, session} = ClaudeCode.start_link(
  api_key: "sk-ant-...",
  system_prompt: "You are helpful",
  name: :my_claude
)

# Use application config defaults
# (assumes config is set in config/config.exs)
{:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")
```

### Making Queries (Updated for Phase 4!)

```elixir
# Synchronous query (blocks until complete)
{:ok, response} = ClaudeCode.query_sync(session, "Explain GenServers")

# With query-level option overrides (NEW!)
{:ok, response} = ClaudeCode.query_sync(session, "Complex task",
  system_prompt: "Focus on performance",
  timeout: 120_000,
  allowed_tools: ["Bash(git:*)"]
)

# Streaming query with option overrides
session
|> ClaudeCode.query("Write Elixir code",
     system_prompt: "Use modern Elixir patterns",
     timeout: 180_000)
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Handle errors
case ClaudeCode.query_sync(session, prompt) do
  {:ok, response} -> IO.puts(response)
  {:error, :timeout} -> IO.puts("Request timed out")
  {:error, {:cli_not_found, msg}} -> IO.puts("CLI error: #{msg}")
  {:error, {:claude_error, msg}} -> IO.puts("Claude error: #{msg}")
end
```

### Session Management

```elixir
# Check if a session is alive
ClaudeCode.alive?(session)  # => true/false

# Stop a session
ClaudeCode.stop(session)
```

## Roadmap Highlights

### ✅ Phase 1: MVP (Complete)
- [x] Basic session management
- [x] Synchronous query interface
- [x] Simple text responses
- [x] Error handling

### ✅ Phase 2: Message Types (Complete)
- [x] Parse all Claude message types
- [x] Content block handling
- [x] Pattern matching support

### ✅ Phase 3: Streaming (Complete)
- [x] Native Elixir streams
- [x] Real-time response handling
- [x] Stream utilities for text and tool extraction
- [x] Buffered text output
- [x] Message type filtering

### ✅ Phase 4: Options & Configuration (Complete)
- [x] Flattened options API (no nested :options key)
- [x] NimbleOptions validation with helpful error messages
- [x] Session-level and query-level options
- [x] Option precedence: query > session > app config > defaults
- [x] Application configuration support
- [x] CLI flag conversion for all options

### 🚧 Phase 5: Permission System (Next)
- [ ] Permission handler behaviour
- [ ] Built-in permission modes
- [ ] Custom permission handlers
- [ ] Security controls for tool usage

See the [Roadmap](docs/ROADMAP.md) for the complete implementation plan.

## Architecture

The SDK uses a GenServer-based architecture where each Claude session is a separate process:

```
┌─────────────┐     ┌─────────────────┐     ┌──────────────┐
│ Your Code   │────▶│ ClaudeCode API  │────▶│ Session      │
└─────────────┘     └─────────────────┘     │ (GenServer)  │
                                            └──────┬───────┘
                                                   │
                                            ┌──────▼───────┐
                                            │ CLI Process  │
                                            │ (Port)       │
                                            └──────────────┘
```

- Each session spawns a new Claude CLI subprocess
- Communication happens via JSON streaming over stdout
- The CLI process exits after each query (stateless)
- API keys are passed via environment variables for security

## Testing

The project includes comprehensive tests:

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run only integration tests
mix test --only integration
```

Tests use mock CLI scripts to simulate Claude behavior without requiring API access.

## Troubleshooting

### CLI Not Found

If you get a `{:error, {:cli_not_found, _}}` error:

1. Ensure Claude CLI is installed: `claude --version`
2. Make sure `claude` is in your PATH
3. Try running `ClaudeCode.CLI.validate_installation()` to debug

### Authentication Errors

If you get authentication errors:

1. Check your API key is valid
2. Ensure it's properly set: `export ANTHROPIC_API_KEY="sk-ant-..."`
3. Try a simple test: `claude "Hello"`

### Timeout Errors

For long-running queries:

```elixir
# Increase the timeout (default is 60 seconds)
{:ok, response} = ClaudeCode.query_sync(session, prompt, timeout: 300_000)
```

### Streaming API Issues

If you're getting errors when using the streaming API:

**KeyError when accessing message content:**

```elixir
# ❌ Wrong - trying to access .content directly
session
|> ClaudeCode.query("Hello")
|> Stream.each(&IO.write(&1.content))  # This will fail!

# ✅ Correct - use the text_content helper
session
|> ClaudeCode.query("Hello")
|> ClaudeCode.Stream.text_content()
|> Stream.each(&IO.write/1)

# ✅ Or access the nested structure correctly
session
|> ClaudeCode.query("Hello")
|> Stream.each(fn
  %ClaudeCode.Message.Assistant{message: %{content: content}} ->
    Enum.each(content, fn
      %ClaudeCode.Content.Text{text: text} -> IO.write(text)
      _ -> :ok
    end)
  _ -> :ok
end)
```

Remember: Assistant messages have a nested structure where content is at `message.content`, not directly on the struct.

## Project Goals

1. **Idiomatic Elixir** - Leverage OTP patterns and Elixir conventions
2. **Production Ready** - Built for reliability and observability
3. **Developer Friendly** - Simple API with powerful capabilities
4. **Phoenix Integration** - First-class support for LiveView

## Complete API Reference

### ClaudeCode Module

```elixir
# Start a new session with flattened options
ClaudeCode.start_link(opts)
# Options:
#   - api_key: String.t() (required)
#   - model: String.t() (optional, default: "sonnet")  
#   - system_prompt: String.t() (optional)
#   - allowed_tools: [String.t()] (optional, e.g. ["View", "Bash(git:*)"])
#   - max_conversation_turns: integer() (optional, default: 50)
#   - working_directory: String.t() (optional)
#   - permission_mode: atom() (optional, default: :ask_always)
#   - timeout: timeout() (optional, default: 300_000)
#   - permission_handler: atom() (optional)
#   - name: atom() (optional, for named GenServer)

# Synchronous query with optional overrides
ClaudeCode.query_sync(session, prompt, opts \\ [])
# Query Options:
#   - system_prompt: String.t() (override session default)
#   - timeout: timeout() (override session default)
#   - allowed_tools: [String.t()] (override session default)
# Returns: {:ok, String.t()} | {:error, term()}

# Streaming query with optional overrides (returns Elixir Stream)
ClaudeCode.query(session, prompt, opts \\ [])
# Same query options as above
# Returns: Stream.t()

# Async query with optional overrides (messages sent to calling process)
ClaudeCode.query_async(session, prompt, opts \\ [])
# Same query options as above
# Returns: {:ok, reference()} | {:error, term()}

# Session management
ClaudeCode.alive?(session)      # Check if session is running
ClaudeCode.stop(session)        # Stop the session
```

### ClaudeCode.Stream Module

```elixir
# Create a stream (called internally by ClaudeCode.query/3)
Stream.create(session, prompt, opts \\ [])

# Extract text content from assistant messages
Stream.text_content(stream)
# Returns: Stream.t() of String.t()

# Extract tool use blocks
Stream.tool_uses(stream)
# Returns: Stream.t() of Content.ToolUse.t()

# Filter messages by type
Stream.filter_type(stream, type)
# Types: :system | :assistant | :user | :result | :tool_use

# Take messages until result is received
Stream.until_result(stream)
# Returns: Stream.t() that stops after result

# Buffer text until sentence boundaries
Stream.buffered_text(stream)
# Returns: Stream.t() of complete sentences
```

### Message Types Reference

All message types follow the official Claude SDK schema:

```elixir
# Base message types
ClaudeCode.Message.System.t()
ClaudeCode.Message.Assistant.t()
ClaudeCode.Message.User.t()
ClaudeCode.Message.Result.t()

# Content block types
ClaudeCode.Content.Text.t()
ClaudeCode.Content.ToolUse.t()
ClaudeCode.Content.ToolResult.t()

# Pattern matching examples
case message do
  %Message.Assistant{message: %{content: content}} ->
    # Process assistant content
  %Message.Result{is_error: true, result: error} ->
    # Handle error
  %Message.Result{result: text} ->
    # Handle success
  _ ->
    # Other message types
end
```

### Error Handling

The SDK provides detailed error information:

```elixir
# CLI errors
{:error, {:cli_not_found, message}}
{:error, {:cli_exit, exit_code}}
{:error, {:port_closed, reason}}

# Claude API errors (via Result message)
%Message.Result{
  is_error: true,
  subtype: :error_max_turns,  # or :error_during_execution
  result: "Error details..."
}

# Stream errors
{:stream_init_error, reason}
{:stream_error, error}
{:stream_timeout, request_ref}
```

## Examples

See the [examples](examples/) directory for complete working examples:
- `streaming_example.exs` - Comprehensive streaming API usage
- More examples coming soon!

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- Built on top of the [Claude Code CLI](https://github.com/anthropics/claude-code)
- Inspired by the [Python SDK](https://github.com/anthropics/claude-code-sdk-python)
- Designed for the Elixir community
