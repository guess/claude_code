# Streaming Guide

ClaudeCode offers two ways to get responses: synchronous queries and streaming. This guide covers when and how to use each.

## Synchronous vs Streaming

**Synchronous** - Wait for the complete response:
```elixir
{:ok, response} = ClaudeCode.query(session, "Explain GenServers")
IO.puts(response)  # Full response at once
```

**Streaming** - Process response as it arrives:
```elixir
session
|> ClaudeCode.query_stream("Explain GenServers")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)  # Prints incrementally
```

| Use Case | Recommended |
|----------|-------------|
| Simple queries, scripts | Synchronous |
| Chat interfaces, LiveView | Streaming |
| Long responses | Streaming |
| Batch processing | Synchronous |

## Stream Utilities

The `ClaudeCode.Stream` module provides utilities for working with streams:

```elixir
alias ClaudeCode.Stream

# Extract text content from assistant messages
stream |> Stream.text_content() |> Enum.each(&IO.write/1)

# Extract thinking content (for extended thinking models)
stream |> Stream.thinking_content() |> Enum.to_list()

# Extract tool usage blocks
stream |> Stream.tool_uses() |> Enum.each(&handle_tool/1)

# Filter by message type
stream |> Stream.filter_type(:assistant) |> Enum.to_list()

# Buffer text until sentence boundaries
stream |> Stream.buffered_text() |> Enum.each(&process_sentence/1)

# Take messages until result is received
stream |> Stream.until_result() |> Enum.to_list()
```

## Character-Level Streaming

For real-time chat interfaces, enable partial messages to receive text character-by-character:

```elixir
session
|> ClaudeCode.query_stream("Tell me a story", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(&IO.write/1)
```

### Delta Utilities

```elixir
# Text deltas only (most common)
ClaudeCode.Stream.text_deltas(stream)

# Thinking deltas (extended thinking)
ClaudeCode.Stream.thinking_deltas(stream)

# All delta types with index
ClaudeCode.Stream.content_deltas(stream)
```

### Comparing Modes

```elixir
# Default: Complete chunks
stream |> Stream.text_content() |> Enum.to_list()
# => ["Hello! How can I help you today?"]

# Partial: Character deltas
stream |> Stream.text_deltas() |> Enum.to_list()
# => ["Hello", "!", " How", " can", " I", " help", ...]
```

## Working with Stream Events

For advanced use cases, work with raw `StreamEvent` structs:

```elixir
alias ClaudeCode.Message.StreamEvent

session
|> ClaudeCode.query_stream("Hello", include_partial_messages: true)
|> Elixir.Stream.each(fn
  %StreamEvent{event: %{type: :message_start}} ->
    IO.puts("Message started")

  %StreamEvent{event: %{type: :content_block_start, index: idx}} ->
    IO.puts("Content block #{idx} started")

  %StreamEvent{} = event when StreamEvent.text_delta?(event) ->
    IO.write(StreamEvent.get_text(event))

  %StreamEvent{event: %{type: :content_block_stop}} ->
    IO.puts("\nContent block complete")

  %StreamEvent{event: %{type: :message_stop}} ->
    IO.puts("Message complete")

  _other ->
    :ok
end)
|> Elixir.Stream.run()
```

## Performance Metrics

Track time-to-first-token and throughput:

```elixir
defmodule StreamMetrics do
  def measure_ttft(session, prompt) do
    start = System.monotonic_time(:millisecond)

    {first_chunk_time, chunks} =
      session
      |> ClaudeCode.query_stream(prompt, include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Elixir.Stream.with_index()
      |> Enum.reduce({nil, []}, fn {chunk, idx}, {ttft, acc} ->
        now = System.monotonic_time(:millisecond)
        ttft = if idx == 0, do: now - start, else: ttft
        {ttft, [chunk | acc]}
      end)

    total_time = System.monotonic_time(:millisecond) - start
    text = chunks |> Enum.reverse() |> Enum.join()

    %{
      time_to_first_token_ms: first_chunk_time,
      total_time_ms: total_time,
      chunk_count: length(chunks),
      character_count: String.length(text),
      chars_per_second: String.length(text) / (total_time / 1000)
    }
  end
end
```

## Error Handling

```elixir
try do
  session
  |> ClaudeCode.query_stream(prompt)
  |> ClaudeCode.Stream.text_content()
  |> Enum.each(&IO.write/1)
rescue
  e in RuntimeError -> IO.puts("Stream error: #{inspect(e)}")
end
```

## Memory Efficiency

For large responses, process chunks immediately instead of accumulating:

```elixir
# Good: Process immediately
session
|> ClaudeCode.query_stream(prompt)
|> ClaudeCode.Stream.text_content()
|> Elixir.Stream.each(&IO.write/1)
|> Elixir.Stream.run()

# Avoid: Accumulating all chunks
chunks =
  session
  |> ClaudeCode.query_stream(prompt)
  |> ClaudeCode.Stream.text_content()
  |> Enum.to_list()  # Loads everything into memory
```

## Next Steps

- [Phoenix Integration](../integration/phoenix.md) - LiveView streaming
- [Sessions Guide](sessions.md) - Multi-turn conversations
- [Examples](../reference/examples.md) - More patterns
