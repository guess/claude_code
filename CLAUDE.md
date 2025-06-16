# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the ClaudeCode Elixir SDK - an idiomatic Elixir interface to the Claude Code CLI. The SDK spawns the `claude` command as a subprocess and communicates via streaming JSON over stdout.

## Common Development Commands

### Quality Checks
```bash
mix quality          # Run all code quality checks (compile, format, credo, dialyzer)
mix format           # Format code with Styler
mix credo --strict   # Run Credo analysis
mix dialyzer         # Run Dialyzer type checking
```

### Testing
```bash
mix test                        # Run all tests
mix test test/path/to_test.exs # Run specific test file
mix test.all                    # Run tests with coverage report
mix coveralls.html              # Generate HTML coverage report
```

### Development
```bash
mix deps.get         # Install dependencies
iex -S mix           # Start interactive shell with project loaded
mix docs             # Generate documentation
```

## Architecture

The SDK works by spawning the Claude Code CLI (`claude` command) as a subprocess using a shell wrapper:

1. **ClaudeCode.Session** - GenServer that manages the CLI subprocess lifecycle
2. **ClaudeCode.CLI** - Finds the claude binary and builds command arguments
3. **Port** - Uses shell wrapper (`/bin/sh -c`) to prevent CLI hanging
4. **JSON Streaming** - CLI outputs newline-delimited JSON messages (system, assistant, result)

Key CLI flags used:
- `--output-format stream-json` - Get structured JSON output
- `--verbose` - Include all message types
- `--print` - Non-interactive mode

## Current Implementation Status

Phase 4 (Options & Configuration) is COMPLETE! ✅

Implemented:
- Phase 1: Basic session management with GenServer
- Phase 1: Synchronous query interface
- Phase 1: JSON message parsing from CLI stdout (system, assistant, result messages)
- Phase 1: Error handling for CLI not found and auth errors
- Phase 1: Shell wrapper to prevent CLI hanging
- Phase 2: Complete message type parsing matching official SDK schema
- Phase 2: Content block handling (Text, ToolUse, ToolResult) with proper struct types
- Phase 2: Nested message structure for Assistant/User messages
- Phase 3: Streaming support with native Elixir Streams
- Phase 3: Real-time message processing with stream utilities
- Phase 3: Async query support with message delivery
- Phase 4: Flattened options API with NimbleOptions validation
- Phase 4: Option precedence system (Query > Session > App Config > Defaults)
- Phase 4: Application configuration support
- Phase 4: Query-level option overrides

## Testing Approach

- Unit tests mock the Port for predictable message sequences
- Integration tests use a mock CLI script when the real CLI isn't available
- Property-based testing with StreamData for message parsing
- All new code requires tests

## Important Implementation Notes

- The SDK does NOT make direct API calls - all API communication is handled by the CLI
- Each query spawns a new CLI subprocess (the CLI exits after each query)
- API keys are passed via environment variables, never in command arguments
- CLI requires shell wrapper with stdin redirect to prevent hanging
- Response content comes from the "result" message, not "assistant" messages
- Uses `/bin/sh -c` with proper shell escaping for special characters

## File Structure

- `lib/claude_code/` - Main implementation
  - `session.ex` - GenServer for session management with options validation
  - `cli.ex` - CLI binary detection and command building with options support
  - `options.ex` - Options validation & CLI conversion (NimbleOptions)
  - `stream.ex` - Stream utilities for real-time processing
  - `message.ex` - Unified message parsing
  - `content.ex` - Content block parsing
  - `types.ex` - Type definitions matching SDK schema
  - `message/` - Message type modules (system, assistant, user, result)
  - `content/` - Content block modules (text, tool_use, tool_result)
- `test/` - Test files mirror lib structure
- `docs/` - All documentation (ROADMAP, VISION, ARCHITECTURE)
- `examples/` - Working examples

## Development Workflow

1. Check `docs/ROADMAP.md` for current phase and tasks
2. Write tests first (TDD approach)
3. Implement features
4. Run `mix quality` before committing
5. Update documentation as needed

## API Details for Development

### Complete Options List

**See `ClaudeCode.Options` module documentation** for the authoritative source of all options, including:
- Complete schema definitions with NimbleOptions validation
- Type specifications and documentation
- Default values and precedence rules
- CLI flag mappings

Quick reference for development:
- `api_key` (required) - Anthropic API key  
- Options grouped by: Claude config, tool control, advanced features, Elixir-specific
- Query options can override session defaults (except `:api_key`, `:name`, `:permission_handler`)

### Message Type Structure

All message types follow the official Claude SDK schema:

```elixir
# System messages
%ClaudeCode.Message.System{message: text}

# Assistant messages (nested structure)
%ClaudeCode.Message.Assistant{
  message: %{
    content: [%ClaudeCode.Content.Text{text: "..."} | %ClaudeCode.Content.ToolUse{...}]
  }
}

# User messages (nested structure)
%ClaudeCode.Message.User{
  message: %{
    content: [%ClaudeCode.Content.Text{text: "..."} | %ClaudeCode.Content.ToolResult{...}]
  }
}

# Result messages (final response)
%ClaudeCode.Message.Result{
  result: "final response text",
  is_error: false,
  subtype: nil  # or :error_max_turns, :error_during_execution
}
```

### Content Block Types

```elixir
# Text content
%ClaudeCode.Content.Text{text: "response text"}

# Tool usage
%ClaudeCode.Content.ToolUse{
  id: "tool_id",
  name: "tool_name",
  input: %{...}
}

# Tool results
%ClaudeCode.Content.ToolResult{
  tool_use_id: "tool_id",
  content: "tool output",
  is_error: false
}
```

### Stream Utilities

```elixir
# Extract only text content from assistant messages
ClaudeCode.Stream.text_content(stream)

# Extract only tool usage blocks
ClaudeCode.Stream.tool_uses(stream)

# Filter by message type
ClaudeCode.Stream.filter_type(stream, :assistant)

# Buffer text until sentence boundaries
ClaudeCode.Stream.buffered_text(stream)

# Take messages until result is received
ClaudeCode.Stream.until_result(stream)
```

### Error Types

```elixir
# CLI errors
{:error, {:cli_not_found, message}}
{:error, {:cli_exit, exit_code}}
{:error, {:port_closed, reason}}

# Claude API errors (via Result message)
%ClaudeCode.Message.Result{
  is_error: true,
  subtype: :error_max_turns,  # or :error_during_execution
  result: "Error details..."
}

# Stream errors
{:stream_init_error, reason}
{:stream_error, error}
{:stream_timeout, request_ref}
```

### Options Validation & Precedence

Options are validated using NimbleOptions and follow this precedence:
1. Query-level options (highest priority)
2. Session-level options
3. Application configuration
4. Default values (lowest priority)

The `ClaudeCode.Options` module handles validation and conversion to CLI flags.

## Development Memories

- When creating mock data for tests, run the real commands and print the outputs so that we can mimic the actual response and make sure we are handling them appropriately.
- CLI messages have evolved through phases - ensure tests cover all message types
- Assistant/User messages use nested structure with `message.content`, not direct `.content`
- Response content comes from "result" message, not "assistant" messages for final answers
- Option validation happens at session start and query time - use NimbleOptions for consistent validation