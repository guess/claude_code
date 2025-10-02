# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Add --settings and --setting-sources CLI options support ([d21137d])
  - `:settings` option accepts file path, JSON string, or map (auto-encoded to JSON)
  - `:setting_sources` option accepts list of sources (user, project, local) as CSV
  - Both options available at session and query level

### Fixed
- Fix CLI streaming by adding explicit output-format support ([3a1c772])

### Documentation
- Add output_format option documentation ([0a228ce])

## [0.3.0] - 2025-06-16

### Added
- **Production Supervision Support:** Added `ClaudeCode.Supervisor` for managing multiple Claude sessions with fault tolerance
  - Static named sessions in supervision tree for long-lived assistants
  - Dynamic session management (start/stop sessions at runtime)
  - Global, local, and registry-based session naming
  - Automatic restart strategies with OTP supervision
  - Production-ready fault tolerance for AI applications
- **Enhanced Session Management:**
  - Named sessions accessible from anywhere in the application
  - Process isolation with independent crash recovery
  - Hot code reloading support for zero-downtime deployments
  - Session lifecycle management (start, restart, terminate, count)

### Changed
- **Documentation:** Updated main module docs to showcase supervision patterns
- **Architecture:** Enhanced to support both static supervised sessions and dynamic on-demand sessions
- **Examples:** Added comprehensive supervision and production usage examples

## [0.2.0] - 2025-06-16

### Added
- **Environment Variable Fallback:** Added support for `ANTHROPIC_API_KEY` environment variable as fallback when no explicit `api_key` option or application config is provided
- **Enhanced Option Precedence:** Updated option precedence chain to: query > session > app config > environment variables > defaults

### Changed
- **BREAKING:** Renamed API functions for better clarity and Elixir conventions:
  - `query_sync/3` → `query/3` (synchronous queries, now the default)
  - `query/3` → `query_stream/3` (streaming queries, explicitly named)
  - `query_async/3` remains unchanged
- **API Ergonomics:** Made `start_link/1` options parameter optional with default empty list for cleaner API when using application configuration

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

