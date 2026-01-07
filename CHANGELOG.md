# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-01-06

### Changed
- **BREAKING: Simplified public API** - Renamed and reorganized query functions ([e7ca31a])
  - `query_stream/3` → `stream/3` - Primary API for session-based streaming queries
  - `query/3` (session-based sync) → Removed - Use `stream/3` instead
  - `query/2` (new) - One-off convenience function with auto session management
  - Migration: Replace `ClaudeCode.query(session, prompt)` with `ClaudeCode.stream(session, prompt) |> Enum.to_list()`
  - Migration: Replace `ClaudeCode.query_stream(session, prompt)` with `ClaudeCode.stream(session, prompt)`

### Added
- **Concurrent request queuing** - Multiple concurrent streams on same session are now properly queued and executed sequentially ([e7ca31a])

### Fixed
- **Named process handling** - Stream cleanup now properly handles named processes (atoms, `:via`, `:global` tuples) ([e7ca31a])

## [0.8.1] - 2026-01-06

### Fixed
- **Process cleanup on stop** - Claude subprocess now properly terminates when calling `ClaudeCode.stop/1` ([a560ff1])

## [0.8.0] - 2026-01-06

### Changed
- **BREAKING: Renamed message type modules** - Added "Message" suffix for clarity
  - `ClaudeCode.Message.Assistant` → `ClaudeCode.Message.AssistantMessage`
  - `ClaudeCode.Message.User` → `ClaudeCode.Message.UserMessage`
  - `ClaudeCode.Message.Result` → `ClaudeCode.Message.ResultMessage`
  - `ClaudeCode.Message.StreamEvent` → `ClaudeCode.Message.StreamEventMessage`
  - New `ClaudeCode.Message.SystemMessage` and `ClaudeCode.Message.CompactBoundaryMessage` message types
- **BREAKING: Renamed content block modules** - Added "Block" suffix for consistency
  - `ClaudeCode.Content.Text` → `ClaudeCode.Content.TextBlock`
  - `ClaudeCode.Content.ToolUse` → `ClaudeCode.Content.ToolUseBlock`
  - `ClaudeCode.Content.ToolResult` → `ClaudeCode.Content.ToolResultBlock`
  - `ClaudeCode.Content.Thinking` → `ClaudeCode.Content.ThinkingBlock`

### Added
- **New system message fields** - Support for additional Claude Code features
  - `:output_style` - Claude's configured output style
  - `:slash_commands` - Available slash commands
  - `:uuid` - Session UUID
- **Extended message type fields** - Better access to API response metadata
  - `AssistantMessage`: `:priority`, `:sequence_id`, `:finalize_stack`
  - `ResultMessage`: `:session_id`, `:duration_ms`, `:usage`, `:parent_message_id`, `:sequence_id`
  - `UserMessage`: `:priority`, `:sequence_id`, `:finalize_stack`

### Fixed
- **`:mcp_servers` option validation** - Fixed handling of MCP server configurations ([0c7e849])

## [0.7.0] - 2026-01-02

### Added
- **`:strict_mcp_config` option** - Control MCP server loading behavior ([a095516])
  - When `true`, ignores global MCP server configurations
  - Useful for disabling all MCP tools: `tools: [], strict_mcp_config: true`
  - Or using only built-in tools: `tools: :default, strict_mcp_config: true`

### Changed
- **BREAKING: `ClaudeCode.query/3` now returns full `%Result{}` struct** instead of just text
  - Before: `{:ok, "response text"}` or `{:error, {:claude_error, "message"}}`
  - After: `{:ok, %ClaudeCode.Message.Result{result: "response text", ...}}` or `{:error, %ClaudeCode.Message.Result{is_error: true, ...}}`
  - Provides access to metadata: `session_id`, `is_error`, `subtype`, `duration_ms`, `usage`, etc.
  - Migration: Change `{:ok, text}` to `{:ok, result}` and use `result.result` to access the response text
  - `Result` implements `String.Chars`, so `IO.puts(result)` prints just the text

### Removed
- **`:input_format` option** - No longer exposed in public API ([c7ebab2])
- **`:output_format` option** - No longer exposed in public API ([c7ebab2])

## [0.6.0] - 2025-12-31

### Added
- **`:mcp_servers` module map format** - Pass Hermes modules with custom environment variables ([63d4b72])
  - Simple form: `%{"tools" => MyApp.MCPServer}`
  - Extended form with env: `%{"tools" => %{module: MyApp.MCPServer, env: %{"DEBUG" => "1"}}}`
  - Custom env is merged with defaults (`MIX_ENV: "prod"`), can override MIX_ENV
  - Updated MCP docs to recommend `mcp_servers` as the primary configuration method
- **`:json_schema` option** - JSON Schema for structured output validation ([485513f])
  - Accepts a map (auto-encoded to JSON) or pre-encoded JSON string
  - Maps to `--json-schema` CLI flag
- **`:max_budget_usd` option** - Maximum dollar amount to spend on API calls ([5bf996a])
  - Accepts float or integer values
  - Maps to `--max-budget-usd` CLI flag
- **`:tools` option** - Specify available tools from the built-in set ([5bf996a])
  - Use `:default` for all tools, `[]` to disable all, or a list of tool names
  - Maps to `--tools` CLI flag
- **`:agent` option** - Agent name for the session ([5bf996a])
  - Different from `:agents` which defines custom agent configurations
  - Maps to `--agent` CLI flag
- **`:betas` option** - Beta headers to include in API requests ([5bf996a])
  - Accepts a list of beta feature names
  - Maps to `--betas` CLI flag

### Removed
- **`query_async/3`** - Removed push-based async API in favor of `query_stream/3`
  - `query_stream/3` provides a more idiomatic Elixir Stream-based API
  - For push-based messaging (LiveView, GenServers), wrap `query_stream/3` in a Task
  - See Phoenix integration guide for migration examples
- **Advanced Streaming API** - Removed low-level streaming functions
  - `receive_messages/2` - Use `query_stream/3` instead
  - `receive_response/2` - Use `query_stream/3 |> ClaudeCode.Stream.until_result()` instead
  - `interrupt/2` - To cancel, use `Task.shutdown/2` on the consuming task

### Changed
- **`ClaudeCode.Stream`** - Now uses pull-based messaging internally instead of process mailbox

## [0.5.0] - 2025-12-30

### Removed
- **`:permission_handler` option** - Removed unimplemented option from session schema

### Added
- **Persistent streaming mode** - Sessions use bidirectional stdin/stdout communication
  - Auto-connect on first query, auto-disconnect on session stop
  - Multi-turn conversations without subprocess restarts
  - New `:resume` option in `start_link/1` for resuming sessions
  - New `ClaudeCode.get_session_id/1` and `ClaudeCode.Input` module
- **Extended thinking support** - `ClaudeCode.Content.Thinking` for reasoning blocks
  - Stream utilities: `ClaudeCode.Stream.thinking_content/1`, `ClaudeCode.Stream.thinking_deltas/1`
  - `StreamEvent` helpers: `thinking_delta?/1`, `get_thinking/1`
- **MCP servers map option** - `:mcp_servers` accepts inline server configurations
  - Supports `stdio`, `sse`, and `http` transport types
- **Character-level streaming** - `include_partial_messages: true` option
  - Stream utilities: `ClaudeCode.Stream.text_deltas/1`, `ClaudeCode.Stream.content_deltas/1`
  - Enables real-time streaming for LiveView applications
- **Tool callback** - `:tool_callback` option for logging/auditing tool usage
  - `ClaudeCode.ToolCallback` module for correlating tool use and results
- **Hermes MCP integration** - Expose Elixir tools to Claude via MCP
  - Optional dependency: `{:hermes_mcp, "~> 0.14", optional: true}`
  - `ClaudeCode.MCP.Config` for generating MCP configuration
  - `ClaudeCode.MCP.Server` for starting Hermes MCP servers

### Changed
- **Minimum Elixir version raised to 1.18**
- `ClaudeCode.Stream.filter_type/2` now supports `:stream_event` and `:text_delta`

## [0.4.0] - 2025-10-02

### Added
- **Custom agents support** - `:agents` option for defining agent configurations
- **Settings options** - `:settings` and `:setting_sources` for team settings

### Changed
- `:api_key` now optional - CLI handles `ANTHROPIC_API_KEY` fallback

### Fixed
- CLI streaming with explicit output-format support

## [0.3.0] - 2025-06-16

### Added
- **`ClaudeCode.Supervisor`** - Production supervision for multiple Claude sessions
  - Static named sessions and dynamic session management
  - Global, local, and registry-based naming
  - OTP supervision with automatic restarts

## [0.2.0] - 2025-06-16

### Added
- `ANTHROPIC_API_KEY` environment variable fallback

### Changed
- **BREAKING:** Renamed API functions:
  - `query_sync/3` → `query/3`
  - `query/3` → `query_stream/3`
- `start_link/1` options now optional (defaults to `[]`)

## [0.1.0] - 2025-06-16

### Added
- **Complete SDK Implementation (Phases 1-4):**
  - Session management with GenServer-based architecture
  - Synchronous queries with `query_sync/3` (renamed to `query/3` in later version)
  - Streaming queries with native Elixir streams via `query/3` (renamed to `query_stream/3` in later version)
  - Async queries with `query_async/3` for manual message handling
  - Complete message type parsing (system, assistant, user, result)
  - Content block handling (text, tool use, tool result) with proper struct types
  - Flattened options API with NimbleOptions validation
  - Option precedence system: query > session > app config > defaults
  - Application configuration support via `config :claude_code`
  - Comprehensive CLI flag mapping for all Claude Code options

- **Core Modules:**
  - `ClaudeCode` - Main interface with session management
  - `ClaudeCode.Session` - GenServer for CLI subprocess management  
  - `ClaudeCode.CLI` - Binary detection and command building
  - `ClaudeCode.Options` - Options validation and CLI conversion
  - `ClaudeCode.Stream` - Stream utilities for real-time processing
  - `ClaudeCode.Message` - Unified message parsing
  - `ClaudeCode.Content` - Content block parsing
  - `ClaudeCode.Types` - Type definitions matching SDK schema

- **Message Type Support:**
  - System messages with session initialization
  - Assistant messages with nested content structure
  - User messages with proper content blocks
  - Result messages with error subtypes
  - Tool use and tool result content blocks

- **Streaming Features:**
  - Native Elixir Stream integration with backpressure handling
  - Stream utilities: `text_content/1`, `tool_uses/1`, `filter_type/2`
  - Buffered text streaming with `buffered_text/1`
  - Concurrent streaming request support
  - Proper stream cleanup and error handling

- **Configuration System:**
  - 15+ configuration options with full validation
  - Support for API key, model, system prompt, allowed tools
  - Permission mode options: `:default`, `:accept_edits`, `:bypass_permissions`
  - Timeout, max turns, working directory configuration
  - Custom permission handler support
  - Query-level option overrides

### Implementation Details
- Flattened options API for intuitive configuration
- Updated CLI flag mappings to match latest Claude Code CLI
- Enhanced error handling with proper message subtypes
- Shell wrapper implementation to prevent CLI hanging
- Proper JSON parsing for all message types
- Concurrent query isolation with dedicated ports
- Memory management for long-running sessions
- Session continuity across multiple queries

### Security
- API keys passed via environment variables only
- Shell command injection prevention with proper escaping
- Subprocess isolation with dedicated ports per query
- No sensitive data in command arguments or logs

### Documentation
- Complete module documentation with doctests
- Comprehensive README with installation and usage examples
- Architecture documentation explaining CLI integration
- Streamlined roadmap focusing on current status and future enhancements

### Testing
- 146+ comprehensive tests covering all functionality
- Unit tests for all modules with mock CLI support
- Integration tests with real CLI when available
- Property-based testing for message parsing
- Stream testing with concurrent scenarios
- Coverage reporting with ExCoveralls

