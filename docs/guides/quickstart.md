# Quickstart

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/quickstart). Examples are adapted for Elixir.

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

Fetch dependencies:

```bash
mix deps.get
```

The Claude CLI binary is automatically installed to `priv/bin/` on first use. To pre-install it (e.g., for CI or releases), run `mix claude_code.install`.

## Authenticate

```bash
# Option A: Use your Claude subscription (no API key needed)
$(mix claude_code.path) /login

# Option B: Use an API key
export ANTHROPIC_API_KEY="sk-ant-..."
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
