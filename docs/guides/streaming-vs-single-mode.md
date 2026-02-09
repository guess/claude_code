# Streaming vs Single Mode

The SDK offers two ways to interact with Claude: single-shot queries and streaming sessions.

## Single Mode: `ClaudeCode.query/2`

Best for one-off questions where you just need the final answer.

```elixir
{:ok, result} = ClaudeCode.query("What is 2 + 2?")
IO.puts(result)
# => "4"

# With options
{:ok, result} = ClaudeCode.query("Summarize this code",
  model: "opus",
  system_prompt: "Be concise"
)
```

`query/2` automatically starts a session, sends the prompt, collects the result, and stops the session. The return value is a `ResultMessage` struct (which implements `String.Chars`).

### Error Handling

```elixir
case ClaudeCode.query("Do something complex") do
  {:ok, result} ->
    IO.puts(result.result)

  {:error, %ClaudeCode.Message.ResultMessage{is_error: true} = result} ->
    IO.puts("Claude error: #{result.result}")

  {:error, reason} ->
    IO.puts("SDK error: #{inspect(reason)}")
end
```

## Streaming Mode: `start_link/1` + `stream/3`

Best for multi-turn conversations, real-time output, and production use.

```elixir
{:ok, session} = ClaudeCode.start_link()

# First turn
session
|> ClaudeCode.stream("Create a GenServer module")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Follow-up turn (maintains conversation context)
session
|> ClaudeCode.stream("Add a handle_cast for incrementing")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stop(session)
```

`stream/3` returns a lazy Elixir `Stream` that emits messages as they arrive. The stream completes when Claude finishes responding.

### Collecting Results

```elixir
# Get just the final text
text = session
|> ClaudeCode.stream("Explain OTP")
|> ClaudeCode.Stream.final_text()

# Get a structured summary
summary = session
|> ClaudeCode.stream("Create some files")
|> ClaudeCode.Stream.collect()

IO.puts(summary.text)
IO.puts("Tools used: #{length(summary.tool_calls)}")
IO.puts("Final: #{summary.result}")
```

### Per-Query Option Overrides

```elixir
{:ok, session} = ClaudeCode.start_link(
  model: "sonnet",
  system_prompt: "You are an Elixir expert"
)

# Override options for a specific query
session
|> ClaudeCode.stream("Complex analysis",
     model: "opus",
     system_prompt: "Provide detailed analysis",
     max_turns: 20)
|> ClaudeCode.Stream.text_content()
|> Enum.join()
```

## When to Use Which

| Use Case | Recommended |
|----------|------------|
| Single question, need answer | `query/2` |
| Multi-turn conversation | `start_link` + `stream/3` |
| Real-time UI updates | `start_link` + `stream/3` |
| Background processing | `start_link` + `stream/3` |
| Production supervision | `start_link` + `stream/3` |
| Script or one-off task | `query/2` |

## Next Steps

- [Streaming Output](streaming-output.md) - Character-level deltas and partial messages
- [Sessions](sessions.md) - Session management, resume, and forking
