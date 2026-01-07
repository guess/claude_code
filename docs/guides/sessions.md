# Sessions Guide

Sessions are the core abstraction in ClaudeCode. A session maintains a persistent connection to Claude and preserves conversation context across queries.

## Starting a Session

```elixir
# Basic - uses ANTHROPIC_API_KEY from environment
{:ok, session} = ClaudeCode.start_link()

# With options
{:ok, session} = ClaudeCode.start_link(
  model: "sonnet",
  system_prompt: "You are an Elixir expert",
  timeout: 120_000
)

# Always stop when done
ClaudeCode.stop(session)
```

## Multi-Turn Conversations

Sessions automatically maintain conversation context:

```elixir
{:ok, session} = ClaudeCode.start_link()

# Claude remembers each exchange
{:ok, _} = ClaudeCode.query(session, "My name is Alice")
{:ok, _} = ClaudeCode.query(session, "I'm learning Elixir")
{:ok, response} = ClaudeCode.query(session, "What's my name and what am I learning?")
# => "Your name is Alice and you're learning Elixir!"

ClaudeCode.stop(session)
```

### Streaming Multi-Turn

Use `stream/3` for real-time responses while maintaining context:

```elixir
{:ok, session} = ClaudeCode.start_link()

# First turn with streaming
session
|> ClaudeCode.stream("My name is Alice")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Second turn - context is preserved
session
|> ClaudeCode.stream("What is my name?")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
# => "Your name is Alice"

ClaudeCode.stop(session)
```

## Resuming Sessions

Save and resume conversations across process restarts:

```elixir
# Get the session ID after a conversation
{:ok, session} = ClaudeCode.start_link()
{:ok, _} = ClaudeCode.query(session, "Remember: the secret code is 12345")
{:ok, session_id} = ClaudeCode.get_session_id(session)
ClaudeCode.stop(session)

# Later: resume with the same context
{:ok, session} = ClaudeCode.start_link(resume: session_id)
{:ok, response} = ClaudeCode.query(session, "What was the secret code?")
# => "The secret code is 12345"
```

## Clearing Context

Start fresh within the same session:

```elixir
ClaudeCode.clear(session)
# Conversation history is cleared, but session stays alive
```

## Named Sessions

Use atoms for easy access across your application:

```elixir
{:ok, _} = ClaudeCode.start_link(name: :assistant)

# Use from anywhere
ClaudeCode.query(:assistant, "Hello!")
```

## Session Lifecycle

| Event | Behavior |
|-------|----------|
| `start_link/1` | Creates GenServer, CLI not started yet |
| First query | CLI subprocess spawns (lazy connect) |
| Subsequent queries | Reuses existing CLI connection |
| `stop/1` | Terminates GenServer and CLI |
| Process crash | GenServer exits, CLI terminates |

## Checking Session State

```elixir
# Check if session is alive
ClaudeCode.alive?(session)

# Get current session ID
{:ok, session_id} = ClaudeCode.get_session_id(session)
```

## Wrapping in GenServer

For production use, wrap sessions in your own GenServer:

```elixir
defmodule ChatAgent do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def chat(message) do
    GenServer.call(__MODULE__, {:chat, message}, 60_000)
  end

  def init(opts) do
    {:ok, session} = ClaudeCode.start_link(opts)
    {:ok, %{session: session}}
  end

  def handle_call({:chat, message}, _from, %{session: session} = state) do
    case ClaudeCode.query(session, message) do
      {:ok, response} -> {:reply, {:ok, response}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def terminate(_reason, %{session: session}) do
    ClaudeCode.stop(session)
  end
end
```

## Session Options

Common options for `start_link/1`:

| Option | Type | Description |
|--------|------|-------------|
| `name` | atom | Register with a name for global access |
| `resume` | string | Session ID to resume |
| `model` | string | Claude model ("sonnet", "opus", etc.) |
| `system_prompt` | string | Override system prompt |
| `timeout` | integer | Query timeout in ms (default: 300_000) |
| `allowed_tools` | list | Tools Claude can use |

See [Configuration Guide](../advanced/configuration.md) for all options.

## Supervised Sessions

For production fault tolerance, use `ClaudeCode.Supervisor`:

```elixir
# In application.ex
children = [
  {ClaudeCode.Supervisor, [
    [name: :assistant],
    [name: :code_reviewer, system_prompt: "You review code"]
  ]}
]

# Sessions restart automatically on crashes
ClaudeCode.query(:assistant, "Hello!")
```

See [Supervision Guide](../advanced/supervision.md) for full production patterns.

## Next Steps

- [Streaming Guide](streaming.md) - Real-time response streaming
- [Supervision Guide](../advanced/supervision.md) - Production patterns
- [Configuration Guide](../advanced/configuration.md) - All options
