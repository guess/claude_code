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

### 3. Anthropic API Key

You'll need an API key from Anthropic.

**Get your API key:**
1. Sign up at [console.anthropic.com](https://console.anthropic.com)
2. Create a new API key
3. Configure it in your application (see Configuration section below)

## Installation

Add ClaudeCode to your project dependencies:

```elixir
# mix.exs
def deps do
  [
    {:claude_code, "~> 0.9.0"}
  ]
end
```

Install dependencies:
```bash
mix deps.get
```

## Configuration

The SDK uses the `ANTHROPIC_API_KEY` environment variable by default. Choose one of these methods:

**Method 1: Environment Variable (Recommended)**
```bash
export ANTHROPIC_API_KEY="sk-ant-your-api-key-here"
```

**Method 2: Application Configuration**
```elixir
# config/config.exs
config :claude_code, api_key: System.get_env("ANTHROPIC_API_KEY")
```

**Method 3: Pass Explicitly**
```elixir
{:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-your-api-key-here")
```

## Your First Query

```elixir
# Start an interactive Elixir session
iex -S mix

# Start a ClaudeCode session
{:ok, session} = ClaudeCode.start_link()

# Send your first query
response =
  session
  |> ClaudeCode.stream("Hello! What's 2 + 2?")
  |> ClaudeCode.Stream.text_content()
  |> Enum.join()

IO.puts(response)
# => "Hello! 2 + 2 equals 4."

# Stop the session when done
ClaudeCode.stop(session)
```

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
  |> ClaudeCode.Stream.text_content()
  |> Enum.join()

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
  |> ClaudeCode.Stream.text_content()
  |> Enum.join()

IO.puts(response)
# => "Your name is Alice and you're learning Elixir!"

ClaudeCode.stop(session)
```

See the [Sessions Guide](sessions.md) for more on multi-turn conversations.

## Error Handling

Always handle potential errors:

```elixir
case ClaudeCode.start_link() do
  {:ok, session} ->
    try do
      response =
        session
        |> ClaudeCode.stream("Hello!")
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      IO.puts("Claude says: #{response}")
    rescue
      e -> IO.puts("Error: #{inspect(e)}")
    after
      ClaudeCode.stop(session)
    end

  {:error, reason} ->
    IO.puts("Failed to start session: #{inspect(reason)}")
end
```

## Next Steps

- [Sessions Guide](sessions.md) - Multi-turn conversations and session management
- [Streaming Guide](streaming.md) - Real-time response streaming
- [Configuration Guide](../advanced/configuration.md) - All configuration options
- [Supervision Guide](../advanced/supervision.md) - Production-ready supervision
- [Troubleshooting](../reference/troubleshooting.md) - Common issues and solutions
