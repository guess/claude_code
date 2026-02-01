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
mix deps.get              # Install dependencies
mix claude_code.install   # Install CLI binary to priv/bin/
iex -S mix                # Start interactive shell with project loaded
mix docs                  # Generate documentation
```

## Architecture

The SDK works by spawning the Claude Code CLI (`claude` command) as a subprocess using a shell wrapper:

1. **ClaudeCode.Session** - GenServer that manages the CLI subprocess lifecycle
2. **ClaudeCode.Installer** - Manages CLI binary installation and resolution
3. **ClaudeCode.CLI** - Finds the claude binary and builds command arguments
4. **Port** - Uses shell wrapper (`/bin/sh -c`) to prevent CLI hanging
5. **JSON Streaming** - CLI outputs newline-delimited JSON messages (system, assistant, result)

Key CLI flags used:
- `--input-format stream-json` - Bidirectional streaming mode (reads from stdin)
- `--output-format stream-json` - Get structured JSON output
- `--verbose` - Include all message types

## Current Implementation Status

**26 features implemented** (96% of core functionality) - See `docs/proposals/FEATURE_MATRIX.md`

Core capabilities:
- CLI installer with automatic binary management
- Session management with GenServer
- Synchronous and async query interface
- Streaming support with native Elixir Streams
- Message parsing (System, Assistant, User, Result, StreamEvent)
- Content blocks (Text, ToolUse, ToolResult, Thinking)
- Options API with NimbleOptions validation
- Model selection with fallback model support
- System prompts (override and append)
- Tool control (allowed/disallowed tools, additional directories)
- Permission modes and MCP integration
- Custom agents configuration
- Team settings loading (file path, JSON, or map)
- Session tracking and auto-resume
- Partial message streaming (character-level deltas)
- Stream utilities (text_deltas, thinking_deltas, buffered_text)
- Interrupt support for in-progress queries

Planned for v1.0 (🔨):
- Session forking (P1 - conversation branching)

## Testing Approach

- Unit tests mock the Port for predictable message sequences
- Integration tests use a mock CLI script when the real CLI isn't available
- Property-based testing with StreamData for message parsing
- All new code requires tests

## Important Implementation Notes

- The SDK does NOT make direct API calls - all API communication is handled by the CLI
- Sessions use a persistent CLI subprocess with bidirectional streaming (stdin/stdout)
- The CLI auto-connects on first query and auto-disconnects on session stop
- API keys are passed via environment variables, never in command arguments
- Response content comes from the "result" message, not "assistant" messages
- Uses `/bin/sh -c` with proper shell escaping for special characters
- Multi-turn conversations are supported via persistent connection (no subprocess restart between queries)

## File Structure

- `lib/claude_code/` - Main implementation
  - `session.ex` - GenServer for session management with options validation
  - `installer.ex` - CLI binary installation and resolution
  - `cli.ex` - CLI binary detection and command building with options support
  - `options.ex` - Options validation & CLI conversion (NimbleOptions)
  - `stream.ex` - Stream utilities for real-time processing
  - `message.ex` - Unified message parsing
  - `content.ex` - Content block parsing
  - `types.ex` - Type definitions matching SDK schema
  - `message/` - Message type modules (system, assistant, user, result)
  - `content/` - Content block modules (text, tool_use, tool_result, thinking)
- `lib/mix/tasks/` - Mix tasks
  - `claude_code.install.ex` - CLI installation mix task
- `test/` - Test files mirror lib structure
- `docs/proposals/` - Feature planning and roadmap
- `examples/` - Working examples

## Development Workflow

1. Check `docs/proposals/FEATURE_MATRIX.md` for prioritized features
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
- `api_key` (optional) - Anthropic API key (defaults to ANTHROPIC_API_KEY env var)
- Options grouped by: Claude config, tool control, advanced features, Elixir-specific
- Query options can override session defaults (except `:api_key` and `:name`)

Key options:
- `:resume` - Session ID to resume a previous conversation (passed to `start_link/1`)
- `:continue` - Continue the most recent conversation in the current directory (boolean)
- `:agents` - Map of custom agent configurations (name -> %{"description" => ..., "prompt" => ..., "tools" => ..., "model" => ...})
- `:settings` - Team settings (file path, JSON string, or map - auto-encoded to JSON)
- `:setting_sources` - List of setting sources ([:user, :project, :local])
- `:plugins` - Plugin configurations (list of paths or maps with type: :local)
- `:allowed_tools` / `:disallowed_tools` - Tool access control
- `:system_prompt` / `:append_system_prompt` - Custom system instructions
- `:model` - Claude model selection
- `:fallback_model` - Fallback model if primary fails
- `:max_turns` - Conversation turn limiting
- `:max_thinking_tokens` - Maximum tokens for thinking blocks
- `:output_format` - Structured output format (map with type: :json_schema and schema keys)
- `:mcp_config` / `:permission_prompt_tool` - MCP integration
- `:add_dir` - Additional accessible directories
- `:include_partial_messages` - Enable character-level streaming
- `:cli_path` - Custom path to Claude CLI binary (highest priority)

Application config options:
- `:cli_version` - Version to install (default: SDK's tested version, currently "2.1.29")
- `:cli_path` - Explicit path to CLI binary (highest priority)
- `:cli_dir` - Directory for downloaded binary (default: priv/bin/)

### Message Type Structure

All message types follow the official Claude SDK schema:

```elixir
# System messages
%ClaudeCode.Message.System{message: text}

# Assistant messages (nested structure)
%ClaudeCode.Message.Assistant{
  message: %{
    content: [%ClaudeCode.Content.TextBlock{text: "..."} | %ClaudeCode.Content.ToolUseBlock{...}],
    context_management: %{...}  # Optional context management info from API
  }
}

# User messages (nested structure)
%ClaudeCode.Message.User{
  message: %{
    content: [%ClaudeCode.Content.TextBlock{text: "..."} | %ClaudeCode.Content.ToolResultBlock{...}]
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
%ClaudeCode.Content.TextBlock{text: "response text"}

# Tool usage
%ClaudeCode.Content.ToolUseBlock{
  id: "tool_id",
  name: "tool_name",
  input: %{...}
}

# Tool results
%ClaudeCode.Content.ToolResultBlock{
  tool_use_id: "tool_id",
  content: "tool output",
  is_error: false
}

# Extended thinking
%ClaudeCode.Content.ThinkingBlock{
  thinking: "reasoning content",
  signature: "signature_value"
}
```

### Stream Utilities

```elixir
# Extract only text content from assistant messages
ClaudeCode.Stream.text_content(stream)

# Extract only thinking content from assistant messages
ClaudeCode.Stream.thinking_content(stream)

# Extract only tool usage blocks
ClaudeCode.Stream.tool_uses(stream)

# Filter by message type
ClaudeCode.Stream.filter_type(stream, :assistant)

# Buffer text until sentence boundaries
ClaudeCode.Stream.buffered_text(stream)

# Take messages until result is received
ClaudeCode.Stream.until_result(stream)

# Character-level streaming (requires include_partial_messages: true)
ClaudeCode.Stream.text_deltas(stream)      # Text character deltas
ClaudeCode.Stream.thinking_deltas(stream)  # Thinking character deltas
ClaudeCode.Stream.content_deltas(stream)   # All delta types with index
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