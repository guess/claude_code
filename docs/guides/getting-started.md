# Getting Started

This guide walks you through setting up and using the ClaudeCode Elixir SDK for the first time.

## Prerequisites

Before you begin, make sure you have:

### 1. Elixir and Mix

ClaudeCode requires Elixir 1.18+ and OTP 27+.

```bash
# Check your versions
elixir --version
# => Elixir 1.18.0 (compiled with Erlang/OTP 27)
```

### 2. Claude Code CLI

The SDK requires the Claude Code CLI to be installed on your system.

**Install the CLI:**
1. Visit [claude.ai/code](https://claude.ai/code)
2. Follow the installation instructions for your platform
3. Verify installation:
   ```bash
   claude --version
   ```

### 3. Authentication

You need either a Claude subscription or an API key.

**Option A: Use your Claude subscription (recommended)**
```bash
claude  # Then type /login to authenticate
```

**Option B: Use an API key**
1. Sign up at [console.anthropic.com](https://console.anthropic.com)
2. Create a new API key
3. Set `ANTHROPIC_API_KEY` environment variable

## Installation

Add ClaudeCode to your project dependencies:

```elixir
# mix.exs
def deps do
  [
    {:claude_code, "~> 0.14"}
  ]
end
```

Install dependencies:
```bash
mix deps.get
```

## Configuration

If you authenticated via `/login`, no configuration is needed - it just works.

For API key usage, set the environment variable:
```bash
export ANTHROPIC_API_KEY="sk-ant-your-api-key-here"
```

## Your First Query

The simplest way to query Claude is with `query/2`:

```elixir
# Start an interactive Elixir session
iex -S mix

# Send a one-off query
{:ok, response} = ClaudeCode.query("Hello! What's 2 + 2?")
IO.puts(response)
# => "Hello! 2 + 2 equals 4."
```

That's it! No session management needed for simple queries.

## Streaming Responses

For real-time responses, use streaming:

```elixir
{:ok, session} = ClaudeCode.start_link()

session
|> ClaudeCode.stream("Explain how GenServers work in Elixir")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stop(session)
```

See the [Streaming Guide](streaming.md) for more details.

## Working with Files

Claude can read and analyze files in your project:

```elixir
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["View", "Edit"]
)

response =
  session
  |> ClaudeCode.stream("Can you look at my mix.exs file and suggest any improvements?")
  |> ClaudeCode.Stream.final_text()

IO.puts(response)
ClaudeCode.stop(session)
```

## Conversation Context

ClaudeCode automatically maintains conversation context:

```elixir
{:ok, session} = ClaudeCode.start_link()

# First message
session |> ClaudeCode.stream("My name is Alice and I'm learning Elixir") |> Stream.run()

# Follow-up message - Claude remembers the context
response =
  session
  |> ClaudeCode.stream("What's my name and what am I learning?")
  |> ClaudeCode.Stream.final_text()

IO.puts(response)
# => "Your name is Alice and you're learning Elixir!"

ClaudeCode.stop(session)
```

See the [Sessions Guide](sessions.md) for more on multi-turn conversations.

## Error Handling

Streams throw on infrastructure errors (CLI crash, timeout). Use `catch` to handle them:

```elixir
case ClaudeCode.start_link() do
  {:ok, session} ->
    try do
      response =
        session
        |> ClaudeCode.stream("Hello!")
        |> ClaudeCode.Stream.final_text()

      IO.puts("Claude says: #{response}")
    catch
      {:stream_init_error, reason} ->
        IO.puts("Failed to start stream: #{inspect(reason)}")

      {:stream_error, reason} ->
        IO.puts("Stream error: #{inspect(reason)}")

      {:stream_timeout, _ref} ->
        IO.puts("Request timed out")
    after
      ClaudeCode.stop(session)
    end

  {:error, reason} ->
    IO.puts("Failed to start session: #{inspect(reason)}")
end
```

Claude API errors (rate limits, max turns) come through as result messages with `is_error: true` - see [Troubleshooting](../reference/troubleshooting.md#error-reference) for details.

## Next Steps

- [Sessions Guide](sessions.md) - Multi-turn conversations and session management
- [Streaming Guide](streaming.md) - Real-time response streaming
- [Configuration Guide](../advanced/configuration.md) - All configuration options
- [Supervision Guide](../advanced/supervision.md) - Production-ready supervision
- [Troubleshooting](../reference/troubleshooting.md) - Common issues and solutions
