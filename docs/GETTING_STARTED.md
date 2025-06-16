# Getting Started

This guide walks you through setting up and using the ClaudeCode Elixir SDK for the first time.

## Prerequisites

Before you begin, make sure you have:

### 1. Elixir and Mix

ClaudeCode requires Elixir 1.16+ and OTP 26+.

```bash
# Check your versions
elixir --version
# => Elixir 1.16.0 (compiled with Erlang/OTP 26)
```

### 2. Claude Code CLI

The SDK requires the Claude Code CLI to be installed on your system.

**Install the CLI:**
1. Visit [claude.ai/code](https://claude.ai/code)
2. Follow the installation instructions for your platform
3. Verify installation:
   ```bash
   claude --version
   # => claude 0.10.1
   ```

### 3. Anthropic API Key

You'll need an API key from Anthropic.

**Get your API key:**
1. Sign up at [console.anthropic.com](https://console.anthropic.com)
2. Create a new API key
3. Set it as an environment variable:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-your-key-here"
   ```

## Installation

Add ClaudeCode to your project dependencies:

```elixir
# mix.exs
def deps do
  [
    {:claude_code, "~> 0.1.0"}
  ]
end
```

Install dependencies:
```bash
mix deps.get
```

## Your First Query

Let's start with a simple example:

```elixir
# Start an interactive Elixir session
iex -S mix

# Start a ClaudeCode session
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Send your first query
{:ok, response} = ClaudeCode.query_sync(session, "Hello! What's 2 + 2?")
IO.puts(response)
# => "Hello! 2 + 2 equals 4."

# Stop the session when done
ClaudeCode.stop(session)
```

## Basic Configuration

Configure your session with common options:

```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "claude-3-5-sonnet-20241022",  # Use a specific model
  system_prompt: "You are a helpful Elixir programming assistant",
  timeout: 120_000  # 2 minute timeout
)
```

## Streaming Responses

For real-time responses, use streaming:

```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Stream the response as it arrives
session
|> ClaudeCode.query("Explain how GenServers work in Elixir")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stop(session)
```

## Working with Files

Claude can read and analyze files in your project:

```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  allowed_tools: ["View", "Edit"]  # Allow file operations
)

{:ok, response} = ClaudeCode.query_sync(session,
  "Can you look at my mix.exs file and suggest any improvements?"
)

IO.puts(response)
ClaudeCode.stop(session)
```

## Conversation Context

ClaudeCode automatically maintains conversation context:

```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# First message
{:ok, _} = ClaudeCode.query_sync(session, "My name is Alice and I'm learning Elixir")

# Follow-up message - Claude remembers the context
{:ok, response} = ClaudeCode.query_sync(session, "What's my name and what am I learning?")
IO.puts(response)
# => "Your name is Alice and you're learning Elixir!"

ClaudeCode.stop(session)
```

## Application Configuration

For production applications, configure defaults in your app config:

```elixir
# config/config.exs
config :claude_code,
  model: "claude-3-5-sonnet-20241022",
  timeout: 180_000,
  system_prompt: "You are a helpful assistant for our Elixir application",
  allowed_tools: ["View"]

# Now sessions use these defaults
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
  # Other options inherited from config
)
```

## Error Handling

Always handle potential errors:

```elixir
case ClaudeCode.start_link(api_key: System.get_env("ANTHROPIC_API_KEY")) do
  {:ok, session} ->
    case ClaudeCode.query_sync(session, "Hello!") do
      {:ok, response} ->
        IO.puts("Claude says: #{response}")
      {:error, :timeout} ->
        IO.puts("Request timed out")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    ClaudeCode.stop(session)

  {:error, reason} ->
    IO.puts("Failed to start session: #{inspect(reason)}")
end
```

## Next Steps

Now that you have ClaudeCode working:

1. **Explore Examples** - Check out [examples](EXAMPLES.md) for real-world usage patterns
2. **Configure for Production** - Learn about advanced options in the main [README](../README.md)
3. **Troubleshooting** - If you run into issues, see [Troubleshooting](TROUBLESHOOTING.md)

## Common First Steps

### For CLI Applications
```elixir
defmodule MyCLI do
  def run(args) do
    {:ok, session} = ClaudeCode.start_link(
      api_key: System.get_env("ANTHROPIC_API_KEY"),
      allowed_tools: ["View", "Edit", "Bash"]
    )

    prompt = Enum.join(args, " ")

    session
    |> ClaudeCode.query(prompt)
    |> ClaudeCode.Stream.text_content()
    |> Enum.each(&IO.write/1)

    ClaudeCode.stop(session)
  end
end
```

### For Web Applications
```elixir
defmodule MyApp.ClaudeService do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def ask_claude(prompt) do
    GenServer.call(__MODULE__, {:query, prompt})
  end

  def init(_) do
    {:ok, session} = ClaudeCode.start_link(
      api_key: System.get_env("ANTHROPIC_API_KEY")
    )
    {:ok, %{session: session}}
  end

  def handle_call({:query, prompt}, _from, %{session: session} = state) do
    case ClaudeCode.query_sync(session, prompt) do
      {:ok, response} -> {:reply, {:ok, response}, state}
      error -> {:reply, error, state}
    end
  end
end
```

You're now ready to start building with ClaudeCode! 🚀
