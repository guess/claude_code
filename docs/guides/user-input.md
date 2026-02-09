# User Input

Manage multi-turn interactions with Claude.

## Multi-Turn Conversations

Sessions maintain conversation context automatically. Each call to `stream/3` continues the conversation:

```elixir
{:ok, session} = ClaudeCode.start_link()

# Turn 1
session
|> ClaudeCode.stream("What is the Fibonacci sequence?")
|> ClaudeCode.Stream.final_text()
|> IO.puts()

# Turn 2 - Claude remembers the context
session
|> ClaudeCode.stream("Write an Elixir function that generates the first N numbers")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Turn 3
session
|> ClaudeCode.stream("Now add memoization")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stop(session)
```

## Interactive Loop

Build a simple REPL-style interaction:

```elixir
{:ok, session} = ClaudeCode.start_link(
  system_prompt: "You are a helpful coding assistant."
)

defmodule ChatLoop do
  def run(session) do
    case IO.gets("You: ") do
      :eof -> :ok
      {:error, _} -> :ok
      input ->
        prompt = String.trim(input)

        unless prompt == "" do
          IO.write("Claude: ")

          session
          |> ClaudeCode.stream(prompt)
          |> ClaudeCode.Stream.text_content()
          |> Enum.each(&IO.write/1)

          IO.puts("")
        end

        run(session)
    end
  end
end

ChatLoop.run(session)
ClaudeCode.stop(session)
```

## Health Checking

Check if a session's CLI subprocess is healthy:

```elixir
case ClaudeCode.health(session) do
  :healthy ->
    IO.puts("Session is ready")

  {:unhealthy, reason} ->
    IO.puts("Session is unhealthy: #{inspect(reason)}")
end
```

## SDK Limitation: canUseTool Callback

The Agent SDK (Python/TypeScript) supports a `canUseTool` callback that runs before each tool execution, allowing you to approve or reject tool use programmatically. This feature is **not yet available** in the Elixir SDK.

Current alternatives:
- Use `permission_mode:` to control overall permission behavior
- Use `allowed_tools:` / `disallowed_tools:` for static tool restrictions
- Use `tool_callback:` for post-execution monitoring (see [Hooks](hooks.md))

## Next Steps

- [Sessions](sessions.md) - Resume, fork, and manage conversation history
- [Hooks](hooks.md) - Monitor tool execution with callbacks
