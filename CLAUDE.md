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

# Distributed tests (Adapter.Node) require a named BEAM node:
elixir --sname test -S mix test --include distributed
```

### Development
```bash
mix deps.get              # Install dependencies
mix claude_code.install   # Install CLI binary to priv/bin/
mix claude_code.uninstall # Remove bundled CLI binary
mix claude_code.path      # Print resolved CLI binary path
iex -S mix                # Start interactive shell with project loaded
mix docs                  # Generate documentation
```

## Architecture

The SDK is organized in three layers:

1. **Adapter-agnostic** — Session, Stream, Options (validation), Types, Message/Content structs
2. **CLI protocol** — CLI.Command (flags), CLI.Input (stdin), CLI.Parser (JSON parsing)
3. **Adapters** — Adapter.Port (local CLI via Port), Adapter.Node (distributed via BEAM), Adapter.Test (in-memory stubs)

Key modules:
- **ClaudeCode.Session** - GenServer that manages the adapter subprocess lifecycle
- **ClaudeCode.Adapter.Port** - Port-based adapter that spawns the CLI as a local subprocess
- **ClaudeCode.Adapter.Node** - Distributed adapter that runs Adapter.Port on a remote BEAM node via Erlang distribution
- **ClaudeCode.CLI** - Thin facade: binary resolution + command building (delegates to Resolver + Command)
- **ClaudeCode.CLI.Command** - Converts Elixir options to CLI flags and builds argument lists
- **ClaudeCode.CLI.Parser** - Parses newline-delimited JSON from CLI output into structs
- **ClaudeCode.Adapter.Port.Installer** - CLI binary download and version management

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
- Session forking (via `:fork_session` option with `:resume`)

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
  - `options.ex` - Options validation (NimbleOptions); `to_cli_args` delegates to CLI.Command
  - `stream.ex` - Stream utilities for real-time processing
  - `types.ex` - Type definitions matching SDK schema
  - `message.ex` - Message type union + helpers; `parse` delegates to CLI.Parser
  - `content.ex` - Content type union + helpers; `parse` delegates to CLI.Parser
  - `message/` - Message type modules (system, assistant, user, result, partial, compact_boundary)
  - `content/` - Content block modules (text, tool_use, tool_result, thinking)
  - `adapter.ex` - Adapter behaviour definition + notification helpers
  - `adapter/`
    - `port.ex` - Port-based CLI adapter GenServer (Port, shell, env, reconnect)
    - `port/`
      - `installer.ex` - CLI binary download and installation
      - `resolver.ex` - CLI binary resolution and validation
    - `node.ex` - Distributed adapter (runs Adapter.Port on a remote BEAM node)
    - `test.ex` - Test adapter (mock)
  - `cli.ex` - Thin facade: find_binary + build_command (delegates to Resolver + Command)
  - `cli/`
    - `command.ex` - CLI flag conversion and argument building (shared CLI protocol)
    - `input.ex` - stream-json stdin message builders (shared CLI protocol)
    - `parser.ex` - JSON → struct parsing (shared CLI protocol)
- `lib/mix/tasks/` - Mix tasks
  - `claude_code.install.ex` - CLI installation mix task
  - `claude_code.uninstall.ex` - CLI binary removal
  - `claude_code.path.ex` - CLI binary path resolution
- `test/` - Test files mirror lib structure
- `docs/plans/` - Design documents and implementation plans
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
- `:agents` - List of `ClaudeCode.Agent` structs or map of custom agent configurations
- `:settings` - Team settings (file path, JSON string, or map - auto-encoded to JSON)
- `:setting_sources` - List of setting sources ([:user, :project, :local])
- `:plugins` - Plugin configurations (list of paths or maps with type: :local)
- `:allowed_tools` / `:disallowed_tools` - Tool access control
- `:system_prompt` / `:append_system_prompt` - Custom system instructions
- `:model` - Claude model selection
- `:fallback_model` - Fallback model if primary fails
- `:max_turns` - Conversation turn limiting
- `:max_thinking_tokens` - Maximum tokens for thinking blocks (deprecated: use `:thinking`)
- `:thinking` - Extended thinking config (`:adaptive`, `{:enabled, budget_tokens: N}`, or `:disabled`)
- `:effort` - Effort level for the session (:low, :medium, :high)
- `:output_format` - Structured output format (map with type: :json_schema and schema keys)
- `:mcp_config` / `:permission_prompt_tool` - MCP integration
- `:add_dir` - Additional accessible directories
- `:include_partial_messages` - Enable character-level streaming
- `:cli_path` - CLI binary resolution mode: `:bundled` (default), `:global`, or explicit path string
- `:sandbox` - Sandbox settings for bash command isolation (map, merged into --settings)
- `:enable_file_checkpointing` - Enable file checkpointing (boolean, set via env var)

Application config options:
- `:cli_version` - Version to install (default: SDK's tested version)
- `:cli_path` - CLI binary resolution mode: `:bundled` (default), `:global`, or explicit path
- `:cli_dir` - Directory for downloaded binary (default: priv/bin/)

### Message Type Structure

All message types follow the official Claude SDK schema:

```elixir
# System messages (init)
%ClaudeCode.Message.SystemMessage{
  type: :system,
  subtype: :init,
  session_id: "uuid",
  tools: ["Bash", "Read", ...],
  model: "claude-sonnet-...",
  permission_mode: :default,
  ...
}

# Assistant messages (nested structure)
%ClaudeCode.Message.AssistantMessage{
  message: %{
    content: [%ClaudeCode.Content.TextBlock{text: "..."} | %ClaudeCode.Content.ToolUseBlock{...}],
    context_management: %{...}  # Optional context management info from API
  }
}

# User messages (nested structure)
%ClaudeCode.Message.UserMessage{
  message: %{
    content: [%ClaudeCode.Content.TextBlock{text: "..."} | %ClaudeCode.Content.ToolResultBlock{...}]
  }
}

# Result messages (final response)
%ClaudeCode.Message.ResultMessage{
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

## Git Conventions

- Never add a "Co-Authored-By" line to commit messages or PR descriptions

## Documentation Conventions

- In CHANGELOG.md, always use fully qualified module names (e.g., `ClaudeCode.Stream.filter_type/2`, not `Stream.filter_type/2`). ExDoc parses the changelog and will emit warnings for unresolved short names.

## Development Memories

- When creating mock data for tests, run the real commands and print the outputs so that we can mimic the actual response and make sure we are handling them appropriately.
- CLI messages have evolved through phases - ensure tests cover all message types
- Assistant/User messages use nested structure with `message.content`, not direct `.content`
- Response content comes from "result" message, not "assistant" messages for final answers
- Option validation happens at session start and query time - use NimbleOptions for consistent validation