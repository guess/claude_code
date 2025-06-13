# ClaudeCode

An Elixir SDK for Claude Code - bringing AI-powered coding assistance to the Elixir ecosystem.

> **Status**: Pre-alpha - This SDK is in early development. See our [Roadmap](ROADMAP.md) for implementation timeline.

## Project Overview

ClaudeCode is an idiomatic Elixir interface to the Claude Code CLI, designed to leverage Elixir's strengths in building concurrent, fault-tolerant applications. The SDK provides a GenServer-based API for managing Claude sessions, with built-in support for streaming, supervision, and Phoenix LiveView integration.

## Documentation

- 📋 **[Roadmap](docs/ROADMAP.md)** - Implementation plan and timeline
- 🔮 **[Vision](docs/VISION.md)** - Complete API documentation and future features
- 🏗️ **[Architecture](docs/ARCHITECTURE.md)** - Technical design decisions
- 🛠️ **[Development Setup](docs/DEV_SETUP.md)** - Developer environment guide

## Current Status

As of now, the project structure has been initialized with:

```
claude_code/
├── README.md          # This file
├── VISION.md          # Future API documentation
├── ROADMAP.md         # Implementation roadmap
├── lib/
│   └── claude_code.ex # Main module (placeholder)
├── mix.exs            # Project configuration
└── test/
    ├── claude_code_test.exs
    └── test_helper.exs
```

## Installation

> **Note**: This package is not yet published to Hex.pm

For development, clone the repository:

```bash
git clone https://github.com/yourusername/claude_code.git
cd claude_code
mix deps.get
```

## Development Setup

1. Install the Claude Code CLI:
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

2. Set your Anthropic API key:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-..."
   ```

3. Run tests:
   ```bash
   mix test
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

## Roadmap Highlights

### Phase 1: MVP (Current Focus)
- [ ] Basic session management
- [ ] Synchronous query interface
- [ ] Simple text responses
- [ ] Error handling

### Phase 2: Message Types
- [ ] Parse all Claude message types
- [ ] Content block handling
- [ ] Pattern matching support

### Phase 3: Streaming
- [ ] Native Elixir streams
- [ ] Real-time response handling

See the [Roadmap](docs/ROADMAP.md) for the complete implementation plan.

## Example Usage (Future API)

```elixir
# Start a session
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Query Claude
{:ok, response} = ClaudeCode.query_sync(session, "Write a hello world function")
IO.puts(response.content)
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