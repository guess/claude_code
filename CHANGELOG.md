# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`ClaudeCode.Agent` struct** - Idiomatic builder for subagent configurations ([1d0188b])
  - `Agent.new/1` accepts keyword options: `:name`, `:description`, `:prompt`, `:model`, `:tools`
  - Pass a list of Agent structs to the `:agents` option instead of raw maps
  - Implements `Jason.Encoder` and `JSON.Encoder` protocols
  - Raw map format remains supported for backwards compatibility

## [0.18.0] - 2026-02-10 | CC 2.1.37

### Breaking

- **SDK bundles its own CLI binary by default** - The SDK now downloads and manages its own Claude CLI in `priv/bin/`, auto-installing on first use. To use a globally installed CLI instead, set `cli_path: :global` or pass an explicit path like `cli_path: "/usr/local/bin/claude"`. The bundled version defaults to the latest CLI version tested with the SDK, configurable via `cli_version`. See `ClaudeCode.Options` for details.

```ex
# config.exs
config :claude_code, cli_path: :global
```

### Added

#### Control protocol

Runtime control of sessions without restarting. See [Sessions — Runtime Control](docs/guides/sessions.md#runtime-control).

- `ClaudeCode.set_model/2` - Change the model mid-conversation ([7ba2007])
- `ClaudeCode.set_permission_mode/2` - Change the permission mode mid-conversation ([7ba2007])
- `ClaudeCode.get_mcp_status/1` - Query MCP server connection status ([7ba2007])
- `ClaudeCode.get_server_info/1` - Get server info cached from handshake ([228c57f])
- `ClaudeCode.rewind_files/2` - Rewind files to a checkpoint. See [File Checkpointing](docs/guides/file-checkpointing.md). ([7ba2007])
- Returns `{:error, :not_supported}` for adapters without control protocol support
- **Initialize handshake** - Adapter sends `initialize` request on startup, transitions through `:initializing` → `:ready`. Agents are now delivered through the handshake (matching the Python SDK) instead of as a CLI flag. See [Subagents](docs/guides/subagents.md). ([228c57f], [2a4473b])

#### New options

- **`:sandbox`** - Sandbox config for bash isolation (map merged into `--settings`). See [Secure Deployment](docs/guides/secure-deployment.md). ([5f48858])
- **`:enable_file_checkpointing`** - Track file changes for rewinding. See [File Checkpointing](docs/guides/file-checkpointing.md). ([5f48858])
- **`:allow_dangerously_skip_permissions`** - Required guard for `permission_mode: :bypass_permissions`. See [Permissions](docs/guides/permissions.md). ([c9dc6fa])
- **`:file`** - File resources (repeatable, format: `file_id:path`) ([d6c1869])
- **`:from_pr`** - Resume session linked to a PR ([d6c1869])
- **`:debug` / `:debug_file`** - Debug mode with optional filter and log file ([d6c1869])

#### Adapter system

Swappable backends for different execution environments.

- **`ClaudeCode.Adapter` behaviour** - 4 callbacks: `start_link/2`, `send_query/4`, `health/1`, `stop/1` ([1582644])
- **Adapter notification helpers** - `notify_message/2`, `notify_done/2`, `notify_error/2`, `notify_status/2` ([1704326])
- **`ClaudeCode.health/1`** - Check adapter health (`:healthy` | `:degraded` | `{:unhealthy, reason}`). See [Hosting](docs/guides/hosting.md). ([383dda6])

#### CLI management

- **`mix claude_code.install`** - Install the bundled CLI binary, auto-updating on version mismatch. ([6e7c837])
- **`mix claude_code.path`** - Print resolved binary path, e.g. `$(mix claude_code.path) /login` ([94b5143])
- **`mix claude_code.uninstall`** - Remove the bundled CLI binary ([6e7c837])

### Changed

- **`:cli_path` resolution modes** - `:bundled` (default), `:global`, or explicit path string. See `ClaudeCode.Options`. ([94b5143])
- **Async adapter provisioning** - `start_link/1` returns immediately; CLI setup runs in the background. Queries queue until ready. ([f1a0875], [91ee60d], [6a60eb4])
- **Schema alignment with CLI v2.1.37** - New fields across message types ([482c603], [42b6c27])
  - `AssistantMessage.error` (`:authentication_failed`, `:billing_error`, `:rate_limit`, `:invalid_request`, `:server_error`, `:unknown`)
  - `UserMessage.tool_use_result`, `ResultMessage.stop_reason`, `AssistantMessage` usage `inference_geo`
  - `SystemMessage` handles all subtypes (init, hook_started, hook_response); `plugins` supports object format

## [0.17.0] 2026-02-01 | CC 2.1.29

### Added

- **`:max_thinking_tokens` option** - Maximum tokens for thinking blocks (integer)
  - Available for both session and query options
  - Maps to `--max-thinking-tokens` CLI flag
- **`:continue` option** - Continue the most recent conversation in the current directory (boolean)
  - Maps to `--continue` CLI flag
  - Aligns with Python/TypeScript SDK `continue` option
- **`:plugins` option** - Load custom plugins from local paths (list of paths or maps)
  - Accepts `["./my-plugin"]` or `[%{type: :local, path: "./my-plugin"}]`
  - Plugin type uses atom `:local` (only supported type currently)
  - Maps to multiple `--plugin-dir` CLI flags
  - Aligns with Python/TypeScript SDK `plugins` option
- **`:output_format` option** - Structured output format configuration (replaces `:json_schema`)
  - Format: `%{type: :json_schema, schema: %{...}}`
  - Currently only `:json_schema` type is supported
  - Maps to `--json-schema` CLI flag
  - Aligns with Python/TypeScript SDK `outputFormat` option
- **`context_management` field in AssistantMessage** - Support for context window management metadata in assistant messages ([f4ea348])
- **CLI installer** - Automatic CLI binary management following phoenixframework/esbuild patterns
  - `mix claude_code.install` - Mix task to install CLI with `--version`, `--if-missing`, `--force` flags
  - `ClaudeCode.Installer` module for programmatic CLI management
  - Uses official Anthropic install scripts (https://claude.ai/install.sh)
  - Binary resolution checks: explicit path → bundled → PATH → common locations
- **`:cli_path` option** - Specify a custom path to the Claude CLI binary
- **Configuration options** for CLI management:
  - `cli_version` - Version to install (default: SDK's tested version)
  - `cli_path` - Explicit path to CLI binary (highest priority)
  - `cli_dir` - Directory for downloaded binary (default: priv/bin/)

## [0.16.0] - 2026-01-27

### Added

- **`:env` option** - Pass custom environment variables to the CLI subprocess ([aa2d3eb])
  - Merge precedence: system env → user `:env` → SDK vars → `:api_key`
  - Useful for MCP tools that need specific env vars or custom PATH configurations
  - Aligns with Python SDK's environment handling

## [0.15.0] - 2026-01-26

### Added

- **Session history reading** - Read and parse conversation history from session files ([ad737ea])
  - `ClaudeCode.conversation/2` - Read conversation (user/assistant messages) by session ID
  - `ClaudeCode.History.list_projects/1` - List all projects with session history
  - `ClaudeCode.History.list_sessions/2` - List all sessions for a project
  - `ClaudeCode.History.read_session/2` - Read all raw entries from a session (low-level)
- **JSON encoding for all structs** - Implement `Jason.Encoder` and `JSON.Encoder` protocols ([a511d5c])
  - All message types: SystemMessage, AssistantMessage, UserMessage, ResultMessage, PartialAssistantMessage, CompactBoundaryMessage
  - All content blocks: TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock
  - Nil values are automatically excluded from encoded output
- **String.Chars for messages and content blocks** - Use `to_string/1` or string interpolation ([b3a9571])
  - `TextBlock` - returns the text content
  - `ThinkingBlock` - returns the thinking content
  - `AssistantMessage` - concatenates all text blocks from the message
  - `PartialAssistantMessage` - returns delta text (empty string for non-text deltas)

### Changed

- **Conversation message parsing refactored** - Extracted to dedicated module with improved error logging ([22c381c])

## [0.14.0] - 2026-01-15

### Added

- **`:session_id` option** - Specify a custom UUID as the session ID for conversations ([2f2c919])
- **`:disable_slash_commands` option** - Disable all skills/slash commands ([16f96b4])
- **`:no_session_persistence` option** - Disable session persistence so sessions are not saved to disk ([16f96b4])
- **New permission modes** - `:delegate`, `:dont_ask`, and `:plan` added to `:permission_mode` option ([16f96b4])
- **New usage tracking fields** - `cache_creation`, `service_tier`, `web_fetch_requests`, `cost_usd`, `context_window`, `max_output_tokens` in result and assistant message usage ([bed060b])
- **New system message fields** - `claude_code_version`, `agents`, `skills`, `plugins` for enhanced session metadata ([bed060b])

### Fixed

- **SystemMessage `slash_commands` and `output_style` parsing** - Fields were always empty/default ([bed060b])
- **ResultMessage `model_usage` parsing** - Per-model token counts and costs were always 0/nil ([bed060b])

## [0.13.3] - 2026-01-14

### Changed

- **`ResultMessage` optional fields use sensible defaults** - `model_usage` defaults to `%{}` and `permission_denials` defaults to `[]` instead of `nil` ([cda582b])

### Fixed

- **`ResultMessage.result` is now optional** - Error messages from the CLI may contain an `errors` array instead of a `result` field. The field no longer crashes when nil and displays errors appropriately ([c06e825])

## [0.13.2] - 2026-01-08

### Fixed

- **`ToolResultBlock` content parsing** - When CLI returns content as a list of text blocks, they are now parsed into `TextBlock` structs instead of raw maps ([5361e2d])

## [0.13.1] - 2026-01-07

### Changed

- **Simplified test stub naming** - Default stub name changed from `ClaudeCode.Session` to `ClaudeCode` ([2fd244f])
  - Config: `adapter: {ClaudeCode.Test, ClaudeCode}` instead of `{ClaudeCode.Test, ClaudeCode.Session}`
  - Stubs: `ClaudeCode.Test.stub(ClaudeCode, fn ...)` instead of `stub(ClaudeCode.Session, fn ...)`
  - Custom names still supported for multiple stub behaviors in same test

### Added

- **`tool_result/2` accepts maps** - Maps are automatically JSON-encoded ([6d9fca6])
  - Example: `ClaudeCode.Test.tool_result(%{status: "success", data: [1, 2, 3]})`

### Fixed

- **`tool_result` content format** - Content is now `[TextBlock.t()]` instead of plain string ([dfba539])
  - Matches MCP `CallToolResult` format where content is an array of content blocks
  - Fixes compatibility with code expecting `content: [%{"type" => "text", "text" => ...}]`

## [0.13.0] - 2026-01-07

### Added

- **`ClaudeCode.Test` module** - Req.Test-style test helpers for mocking Claude responses ([9f78103])
  - `stub/2` - Register function or static message stubs for test isolation
  - `allow/3` - Share stubs with spawned processes for async tests
  - `set_mode_to_shared/0` - Enable shared mode for integration tests
  - Message helpers: `text/2`, `tool_use/3`, `tool_result/2`, `thinking/2`, `result/2`, `system/1`
  - Auto-generates system/result messages, links tool IDs, unifies session IDs
  - Uses `NimbleOwnership` for process-based isolation with `async: true` support
- **`ClaudeCode.Test.Factory` module** - Test data generation for all message and content types ([54dcfd7])
  - Struct factories: `assistant_message/1`, `user_message/1`, `result_message/1`, `system_message/1`
  - Content block factories: `text_block/1`, `tool_use_block/1`, `tool_result_block/1`, `thinking_block/1`
  - Stream event factories for partial message testing
  - Convenience functions with positional arguments for common cases
- **Testing guide** - Comprehensive documentation for testing ClaudeCode integrations ([7dfe509])

## [0.12.0] - 2026-01-07

### Added

- **New stream helpers** for common use cases ([0775bd4])
  - `final_text/1` - Returns only the final result text, simplest way to get Claude's answer
  - `collect/1` - Returns structured summary with text, thinking, tool_calls, and result
  - `tap/2` - Side-effect function for logging/monitoring without filtering the stream
  - `on_tool_use/2` - Callback invoked for each tool use, useful for progress indicators

### Changed

- **`collect/1` returns `tool_calls` instead of `tool_uses`** ([7eebfeb])
  - Now returns `{tool_use, tool_result}` tuples pairing each tool invocation with its result
  - If a tool use has no matching result, the result will be `nil`
  - Migration: Change `summary.tool_uses` to `summary.tool_calls` and update iteration to handle tuples

### Removed

- **`buffered_text/1` stream helper** - Use `final_text/1` or `collect/1` instead ([4a1ee97])

## [0.11.0] - 2026-01-07

### Changed

- **Renamed `StreamEventMessage` to `PartialAssistantMessage`** - Aligns with TypeScript SDK naming (`SDKPartialAssistantMessage`)
  - `ClaudeCode.Message.StreamEventMessage` → `ClaudeCode.Message.PartialAssistantMessage`
  - The struct still uses `type: :stream_event` to match the wire format
  - Helper function renamed: `stream_event?/1` → `partial_assistant_message?/1`

### Added

- **`:fork_session` option** - Create a new session ID when resuming a conversation
  - Use with `:resume` to branch a conversation: `start_link(resume: session_id, fork_session: true)`
  - Original session continues unchanged, fork gets its own session ID after first query

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
  - `ClaudeCode.Message.StreamEvent` → `ClaudeCode.Message.PartialAssistantMessage`
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

- **BREAKING: `ClaudeCode.query` now returns full `%Result{}` struct** instead of just text
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
- Streamlined roadmap focusing on current status and future enhancements

### Testing

- 146+ comprehensive tests covering all functionality
- Unit tests for all modules with mock CLI support
- Integration tests with real CLI when available
- Property-based testing for message parsing
- Stream testing with concurrent scenarios
- Coverage reporting with ExCoveralls
