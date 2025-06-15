# ClaudeCode

An idiomatic Elixir SDK for Claude Code - bringing AI-powered coding assistance to the Elixir ecosystem.

ClaudeCode provides a GenServer-based interface to the Claude Code CLI with support for streaming responses, concurrent queries, and Phoenix LiveView integration.

## Prerequisites

1. **Install Claude Code CLI**:
   - Visit [claude.ai/code](https://claude.ai/code)
   - Follow the installation instructions for your platform
   - Verify installation: `claude --version`

2. **Get an API Key**:
   - Sign up at [console.anthropic.com](https://console.anthropic.com)
   - Create an API key and set it as an environment variable:
     ```bash
     export ANTHROPIC_API_KEY="sk-ant-..."
     ```

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:claude_code, github: "guess/claude_code", branch: "main"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Quick Start

### Basic Usage

```elixir
# Start a session
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Send a query and get a response
{:ok, response} = ClaudeCode.query_sync(session, "Hello, Claude!")
IO.puts(response)
# => "Hello! How can I assist you today?"

# Stop the session when done
ClaudeCode.stop(session)
```

### Configuration

Configure sessions with various options:

```elixir
# Session with custom configuration
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "opus",
  system_prompt: "You are an Elixir expert",
  allowed_tools: ["View", "GlobTool", "Bash(git:*)"],
  timeout: 120_000
)

# Use application configuration for defaults
# config/config.exs
config :claude_code,
  model: "opus",
  timeout: 180_000,
  system_prompt: "You are a helpful Elixir assistant"

# Session automatically uses configured defaults
{:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")
```

### Streaming Responses

Process responses as they arrive:

```elixir
# Stream text content
session
|> ClaudeCode.query("Explain GenServers in Elixir")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# React to tool usage in real-time
session
|> ClaudeCode.query("Create a new Elixir module")
|> ClaudeCode.Stream.tool_uses()
|> Enum.each(fn tool_use ->
  IO.puts("Claude is using: #{tool_use.name}")
end)

# Handle all message types
session
|> ClaudeCode.query("Help me debug this code")
|> Enum.each(fn
  %ClaudeCode.Message.Assistant{message: %{content: content}} ->
    # Process assistant response
  %ClaudeCode.Message.Result{result: result} ->
    # Final result
  _ ->
    # Other message types
    :ok
end)
```

### Query-Level Overrides

Override session defaults for specific queries:

```elixir
# Override options per query
{:ok, response} = ClaudeCode.query_sync(session, "Complex task",
  system_prompt: "Focus on performance optimization",
  timeout: 300_000,
  allowed_tools: ["Bash(git:*)"]
)
```

## API Reference

### ClaudeCode Module

```elixir
# Start a session
ClaudeCode.start_link(opts)
# Options: api_key, model, system_prompt, allowed_tools, max_turns, 
#          cwd, permission_mode, timeout, name

# Synchronous query (blocks until complete)
ClaudeCode.query_sync(session, prompt, opts \\ [])
# Returns: {:ok, String.t()} | {:error, term()}

# Streaming query (returns Elixir Stream)
ClaudeCode.query(session, prompt, opts \\ [])
# Returns: Stream.t()

# Async query (sends messages to calling process)
ClaudeCode.query_async(session, prompt, opts \\ [])
# Returns: {:ok, reference()} | {:error, term()}

# Session management
ClaudeCode.alive?(session)  # Check if session is running
ClaudeCode.stop(session)    # Stop the session
```

### ClaudeCode.Stream Module

```elixir
# Extract text content from responses
ClaudeCode.Stream.text_content(stream)

# Extract tool usage blocks
ClaudeCode.Stream.tool_uses(stream)

# Filter messages by type
ClaudeCode.Stream.filter_type(stream, :assistant)

# Buffer text until sentence boundaries
ClaudeCode.Stream.buffered_text(stream)
```

## Error Handling

```elixir
case ClaudeCode.query_sync(session, "Hello") do
  {:ok, response} -> 
    IO.puts(response)
  {:error, :timeout} -> 
    IO.puts("Request timed out")
  {:error, {:cli_not_found, msg}} -> 
    IO.puts("CLI error: #{msg}")
  {:error, {:claude_error, msg}} -> 
    IO.puts("Claude error: #{msg}")
end
```

## Documentation

- 📋 **[Roadmap](docs/ROADMAP.md)** - Implementation progress and timeline
- 🔮 **[Vision](docs/VISION.md)** - Complete API documentation and future features  
- 🏗️ **[Architecture](docs/ARCHITECTURE.md)** - Technical design decisions
- 🛠️ **[Development Setup](docs/DEV_SETUP.md)** - Developer environment guide

## Examples

See the [examples](examples/) directory for complete working examples:
- `streaming_example.exs` - Comprehensive streaming API usage

## Development

```bash
# Clone and install dependencies
git clone https://github.com/guess/claude_code.git
cd claude_code
mix deps.get

# Run tests
mix test

# Run quality checks (format, credo, dialyzer)
mix quality
```

## Contributing

We welcome contributions! Check the [Roadmap](docs/ROADMAP.md) for current development priorities, then:

1. Pick an unimplemented feature or bug fix
2. Open an issue to discuss your approach  
3. Submit a PR with tests and documentation

## License

MIT License - see [LICENSE](LICENSE) for details.

## Architecture

The SDK uses a GenServer-based architecture where each Claude session is a separate process that spawns the Claude CLI as a subprocess. Communication happens via JSON streaming over stdout, with the CLI process exiting after each query (stateless).

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

Built on top of the [Claude Code CLI](https://github.com/anthropics/claude-code) and designed for the Elixir community.