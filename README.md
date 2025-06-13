# ClaudeCode

An Elixir SDK for Claude Code - bringing AI-powered coding assistance to the Elixir ecosystem.

> **Status**: Alpha (Phase 1 Complete) - Basic functionality is working. See our [Roadmap](docs/ROADMAP.md) for implementation timeline.

## Project Overview

ClaudeCode is an idiomatic Elixir interface to the Claude Code CLI, designed to leverage Elixir's strengths in building concurrent, fault-tolerant applications. The SDK provides a GenServer-based API for managing Claude sessions, with built-in support for streaming, supervision, and Phoenix LiveView integration.

## Documentation

- 📋 **[Roadmap](docs/ROADMAP.md)** - Implementation plan and timeline
- 🔮 **[Vision](docs/VISION.md)** - Complete API documentation and future features
- 🏗️ **[Architecture](docs/ARCHITECTURE.md)** - Technical design decisions
- 🛠️ **[Development Setup](docs/DEV_SETUP.md)** - Developer environment guide

## Current Status

✅ **Phase 1 (MVP) is complete!** The SDK now provides:

- Basic session management with GenServer
- Synchronous query interface 
- JSON message parsing from CLI stdout
- Error handling for common cases
- Comprehensive test suite

```
claude_code/
├── lib/
│   ├── claude_code.ex         # Main API module
│   └── claude_code/
│       ├── session.ex         # GenServer for CLI management
│       ├── cli.ex            # CLI binary handling
│       └── message.ex        # Message parsing
├── test/
│   ├── claude_code_test.exs
│   └── claude_code/
│       ├── session_test.exs
│       ├── cli_test.exs
│       ├── message_test.exs
│       └── integration_test.exs
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

```elixir
# Start a Claude session
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Send a query and get a response
{:ok, response} = ClaudeCode.query_sync(session, "Hello, Claude!")
IO.puts(response)
# => "Hello! How can I assist you today?"

# Check if session is alive
ClaudeCode.alive?(session)
# => true

# Stop the session when done
ClaudeCode.stop(session)
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

### Starting a Session

```elixir
# Basic usage
{:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

# With custom model
{:ok, session} = ClaudeCode.start_link(
  api_key: "sk-ant-...",
  model: "claude-3-opus-20240229"
)

# Named session for easier reference
{:ok, session} = ClaudeCode.start_link(
  api_key: "sk-ant-...",
  name: :my_claude
)
```

### Making Queries

```elixir
# Synchronous query (blocks until complete)
{:ok, response} = ClaudeCode.query_sync(session, "Explain GenServers")

# With custom timeout (default is 60 seconds)
{:ok, response} = ClaudeCode.query_sync(session, "Complex task", timeout: 120_000)

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

### Phase 2: Message Types (Next)
- [ ] Parse all Claude message types
- [ ] Content block handling
- [ ] Pattern matching support

### Phase 3: Streaming
- [ ] Native Elixir streams
- [ ] Real-time response handling

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

## Project Goals

1. **Idiomatic Elixir** - Leverage OTP patterns and Elixir conventions
2. **Production Ready** - Built for reliability and observability
3. **Developer Friendly** - Simple API with powerful capabilities
4. **Phoenix Integration** - First-class support for LiveView

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- Built on top of the [Claude Code CLI](https://github.com/anthropics/claude-code)
- Inspired by the [Python SDK](https://github.com/anthropics/claude-code-sdk-python)
- Designed for the Elixir community