# Quickstart

Get up and running with the ClaudeCode Elixir SDK in under 5 minutes.

## Installation

Add `claude_code` to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:claude_code, "~> 0.17"}
  ]
end
```

Fetch dependencies and install the CLI binary:

```bash
mix deps.get
mix claude_code.install
```

## Set Your API Key

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

Or pass it directly in code:

```elixir
ClaudeCode.query("Hello", api_key: "sk-ant-...")
```

## Your First Query

```elixir
{:ok, result} = ClaudeCode.query("What is the capital of France?")
IO.puts(result)
# => "The capital of France is Paris."
```

## Streaming Responses

```elixir
{:ok, session} = ClaudeCode.start_link()

session
|> ClaudeCode.stream("Write a haiku about Elixir")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stop(session)
```

## Multi-Turn Conversations

```elixir
{:ok, session} = ClaudeCode.start_link()

ClaudeCode.stream(session, "What is 5 + 3?")
|> ClaudeCode.Stream.final_text()
|> IO.puts()

ClaudeCode.stream(session, "Multiply that by 2")
|> ClaudeCode.Stream.final_text()
|> IO.puts()

ClaudeCode.stop(session)
```

## Customization

```elixir
{:ok, session} = ClaudeCode.start_link(
  model: "opus",
  system_prompt: "You are an expert Elixir developer. Be concise.",
  allowed_tools: ["Read", "Bash(mix:*)"],
  max_turns: 10
)
```

## Application Configuration

```elixir
# config/config.exs
config :claude_code,
  model: "sonnet",
  timeout: 120_000,
  allowed_tools: ["Read", "Edit"]
```

## Next Steps

- [Streaming vs Single Mode](streaming-vs-single-mode.md) - When to use `query/2` vs `stream/3`
- [Streaming Output](streaming-output.md) - Character-level streaming and deltas
- [Sessions](sessions.md) - Resume, fork, and manage conversations
- [Permissions](permissions.md) - Control what tools Claude can use
