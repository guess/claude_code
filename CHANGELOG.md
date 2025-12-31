# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

