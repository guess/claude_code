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

Phase 1 (MVP) is COMPLETE! ✅

Implemented:
- Basic session management with GenServer
- Synchronous query interface
- JSON message parsing from CLI stdout (system, assistant, result messages)
- Error handling for CLI not found and auth errors
- Shell wrapper to prevent CLI hanging
- Proper message extraction from result messages

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
  - `session.ex` - GenServer for session management
  - `cli.ex` - CLI binary detection and command building
  - `message.ex` - Message type definitions
- `test/` - Test files mirror lib structure
- `docs/` - All documentation (ROADMAP, VISION, ARCHITECTURE)

## Development Workflow

1. Check `docs/ROADMAP.md` for current phase and tasks
2. Write tests first (TDD approach)
3. Implement features
4. Run `mix quality` before committing
5. Update documentation as needed