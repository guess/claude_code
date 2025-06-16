# Claude Code SDK for Elixir

[![Hex.pm](https://img.shields.io/hexpm/v/claude_code.svg)](https://hex.pm/packages/claude_code)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/claude_code)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/guess/claude_code/blob/main/LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-%3E%3D1.14-purple.svg)](https://elixir-lang.org)

ClaudeCode provides a GenServer-based interface to the Claude Code CLI with support for streaming responses, concurrent queries, and Phoenix LiveView integration.

<div align="center">
    <img src="https://github.com/guess/claude_code/raw/main/docs/claudecode.png" alt="ClaudeCode" width="200">
</div>

## Prerequisites

1. **Install Claude Code CLI**:
   - Visit [claude.ai/code](https://claude.ai/code)
   - Follow the installation instructions for your platform
   - Verify installation: `claude --version`

2. **Get an API Key**:
   - Sign up at [console.anthropic.com](https://console.anthropic.com)
   - Create an API key and configure it (see Configuration section below)

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:claude_code, "~> 0.2.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Quick Start

```elixir
# 1. Configure your API key
config :claude_code, api_key: "sk-ant-your-api-key-here"

# 2. Start a session and query Claude
{:ok, session} = ClaudeCode.start_link()
{:ok, response} = ClaudeCode.query(session, "Hello, Claude!")
IO.puts(response)

# 3. Stream responses in real-time
session
|> ClaudeCode.query_stream("Explain GenServers")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

📖 **[Complete Getting Started Guide →](docs/GETTING_STARTED.md)**

For detailed installation, configuration, and first steps.

## Key Features

### Conversation Continuity
```elixir
{:ok, session} = ClaudeCode.start_link()

# Context is automatically maintained across queries
ClaudeCode.query(session, "My name is Alice")
ClaudeCode.query(session, "What's my name?")  # Remembers "Alice"
```

### Real-time Streaming
```elixir
session
|> ClaudeCode.query_stream("Write a GenServer")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)  # Live text as Claude types
```

### File Operations
```elixir
ClaudeCode.query(session, "Review my mix.exs file", 
  allowed_tools: ["View", "Edit"])
```

## Usage Patterns

### Scripts & Prototyping
```elixir
{:ok, session} = ClaudeCode.start_link()
{:ok, response} = ClaudeCode.query(session, "Explain this concept")
ClaudeCode.stop(session)
```

### Production Applications
```elixir
# Fault-tolerant supervised sessions
{ClaudeCode.Supervisor, [
  [name: :assistant, api_key: api_key],
  [name: :code_reviewer, api_key: api_key]
]}

# Use from anywhere in your app
ClaudeCode.query(:assistant, "Help with this task")
```

## Options Reference

For complete documentation of all available options, see the `ClaudeCode.Options` module:

```elixir
# View session options schema
ClaudeCode.Options.session_schema()

# View query options schema
ClaudeCode.Options.query_schema()
```

**Key points:**
- `:api_key` is required and can be provided via session options or application config
- Query options can override session defaults
- Some options (`:timeout`, `:name`) are Elixir-specific
- Most options map directly to Claude CLI flags

Run `mix docs` and navigate to `ClaudeCode.Options` for detailed option documentation including types, defaults, and validation rules.

## API Reference

### ClaudeCode Module

```elixir
# Start a session
ClaudeCode.start_link(opts)
# See ClaudeCode.Options.session_schema() for all available options

# Synchronous query (blocks until complete)
ClaudeCode.query(session, prompt, opts \\ [])
# Returns: {:ok, String.t()} | {:error, term()}

# Streaming query (returns Elixir Stream)
ClaudeCode.query_stream(session, prompt, opts \\ [])
# Returns: Stream.t()

# Async query (sends messages to calling process)
ClaudeCode.query_async(session, prompt, opts \\ [])
# Returns: {:ok, reference()} | {:error, term()}

# Session management
ClaudeCode.alive?(session)         # Check if session is running
ClaudeCode.stop(session)           # Stop the session
ClaudeCode.get_session_id(session) # Get current session ID for conversation continuity
ClaudeCode.clear(session)  # Clear session to start fresh conversation
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
case ClaudeCode.query(session, "Hello") do
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

- 🚀 **[Getting Started](docs/GETTING_STARTED.md)** - Step-by-step tutorial for new users
- 🏭 **[Production Supervision Guide](docs/SUPERVISION.md)** - Fault-tolerant production deployments
- 💻 **[Examples](docs/EXAMPLES.md)** - Real-world usage patterns and code samples
- 🔧 **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## Production Setup with Supervision

For production applications, use `ClaudeCode.Supervisor` for fault-tolerant AI services with automatic restart capabilities:

```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    MyAppWeb.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :code_reviewer, api_key: api_key, system_prompt: "You review code"],
      [name: :general_assistant, api_key: api_key]
    ]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# Use from anywhere in your app
{:ok, review} = ClaudeCode.query(:code_reviewer, "Review this code")
```

**Key Benefits:**
- ✅ **Fault tolerance** - Sessions restart automatically on crashes
- ✅ **Zero downtime** - Hot code reloading preserves session state
- ✅ **Global access** - Named sessions work from anywhere in your app
- ✅ **Distributed support** - Sessions work across Elixir clusters

📖 **[Complete Production Supervision Guide →](docs/SUPERVISION.md)**

For detailed patterns, examples, and advanced features including dynamic session management, load balancing, monitoring, and distributed deployments.

## Production Usage

### Performance & Concurrency

ClaudeCode is designed for production use with multiple concurrent sessions:

```elixir
# Multiple sessions for parallel processing
sessions = 1..4 |> Enum.map(fn _i ->
  {:ok, session} = ClaudeCode.start_link()
  session
end)

# Process tasks in parallel
results = Task.async_stream(tasks, fn task ->
  session = Enum.random(sessions)  # Simple load balancing
  ClaudeCode.query(session, task.prompt)
end, max_concurrency: 4)

# Clean up
Enum.each(sessions, &ClaudeCode.stop/1)
```

### Phoenix Integration

```elixir
# Use supervised sessions in Phoenix apps
def start(_type, _args) do
  children = [
    MyAppWeb.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :chat_assistant, api_key: api_key]
    ]}
  ]
end

# In controllers and LiveViews
ClaudeCode.query(:chat_assistant, message)
```

### Best Practices

1. **Session Management:**
   ```elixir
   # ✅ RECOMMENDED: Use supervised sessions for production
   {ClaudeCode.Supervisor, [[name: :assistant, api_key: api_key]]}

   # ✅ Good: Temporary sessions for scripts/one-off tasks
   {:ok, temp} = ClaudeCode.start_link(api_key: api_key)
   result = ClaudeCode.query(temp, prompt)
   ClaudeCode.stop(temp)
   ```

2. **Error Handling:**
   ```elixir
   defp safe_claude_query(session, prompt) do
     case ClaudeCode.query(session, prompt, timeout: 30_000) do
       {:ok, response} -> {:ok, response}
       {:error, :timeout} -> {:error, "Request timed out"}
       {:error, reason} -> {:error, "Claude error: #{inspect(reason)}"}
     end
   end
   ```

3. **Resource Management:**
   ```elixir
   # Always clean up sessions
   try do
     {:ok, session} = ClaudeCode.start_link()
     # ... use session
   after
     ClaudeCode.stop(session)
   end
   ```

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

We welcome contributions! Please:

1. Pick an unimplemented feature or bug fix
2. Open an issue to discuss your approach
3. Submit a PR with tests and documentation

## License

MIT License

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
