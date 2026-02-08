# Streaming Guide

ClaudeCode offers two ways to get responses: one-off queries and session-based streaming. This guide covers when and how to use each.

## One-off vs Session-based

**One-off** - Single query with automatic session management:
```elixir
{:ok, response} = ClaudeCode.query("Explain GenServers")
IO.puts(response)  # Full response at once
```

**Session-based Streaming** - Multi-turn with real-time responses:
```elixir
{:ok, session} = ClaudeCode.start_link()

session
|> ClaudeCode.stream("Explain GenServers")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)  # Prints incrementally

ClaudeCode.stop(session)
```

| Use Case | Recommended |
|----------|-------------|
| Simple queries, scripts | One-off (`query/2`) |
| Chat interfaces, LiveView | Session + `stream/3` |
| Multi-turn conversations | Session + `stream/3` |
| Batch processing | One-off (`query/2`) |

## Stream Utilities

The `ClaudeCode.Stream` module provides utilities for working with streams:

### Getting the Final Result

```elixir
alias ClaudeCode.Stream

# Most common: just get the final answer
result = session
|> ClaudeCode.stream("What is 2 + 2?")
|> Stream.final_text()
# => "2 + 2 equals 4."
```

### Collecting a Summary

```elixir
# Get a structured summary of the entire conversation
summary = session
|> ClaudeCode.stream("Create a hello.txt file")
|> Stream.collect()

IO.puts("Text: #{summary.text}")
IO.puts("Result: #{summary.result}")
IO.puts("Tool calls: #{length(summary.tool_calls)}")

# Process each tool call with its result
Enum.each(summary.tool_calls, fn {tool_use, tool_result} ->
  IO.puts("Tool: #{tool_use.name}")
  if tool_result, do: IO.puts("Output: #{tool_result.content}")
end)
```

### Filtering and Extracting Content

```elixir
# Extract text content from assistant messages
stream |> Stream.text_content() |> Enum.each(&IO.write/1)

# Extract thinking content (for extended thinking models)
stream |> Stream.thinking_content() |> Enum.to_list()

# Extract tool usage blocks
stream |> Stream.tool_uses() |> Enum.each(&handle_tool/1)

# Filter by message type
stream |> Stream.filter_type(:assistant) |> Enum.to_list()

# Take messages until result is received
stream |> Stream.until_result() |> Enum.to_list()
```

### Monitoring and Side Effects

```elixir
# Log all messages without affecting the stream
stream
|> Stream.tap(fn msg -> Logger.debug("Got: #{inspect(msg)}") end)
|> Stream.final_text()

# React to tool usage (for progress indicators)
stream
|> Stream.on_tool_use(fn tool ->
  IO.puts("Using tool: #{tool.name}")
end)
|> Stream.final_text()
```

## Character-Level Streaming

For real-time chat interfaces, enable partial messages to receive text character-by-character:

```elixir
session
|> ClaudeCode.stream("Tell me a story", include_partial_messages: true)
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

## Working with Partial Messages

For advanced use cases, work with raw `PartialAssistantMessage` structs:

```elixir
alias ClaudeCode.Message.PartialAssistantMessage

session
|> ClaudeCode.stream("Hello", include_partial_messages: true)
|> Elixir.Stream.each(fn
  %PartialAssistantMessage{event: %{type: :message_start}} ->
    IO.puts("Message started")

  %PartialAssistantMessage{event: %{type: :content_block_start, index: idx}} ->
    IO.puts("Content block #{idx} started")

  %PartialAssistantMessage{} = event when PartialAssistantMessage.text_delta?(event) ->
  IO.write(PartialAssistantMessage.get_text(event))

  %PartialAssistantMessage{event: %{type: :content_block_stop}} ->
    IO.puts("\nContent block complete")

  %PartialAssistantMessage{event: %{type: :message_stop}} ->
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
      |> ClaudeCode.stream(prompt, include_partial_messages: true)
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

## Push-Based Streaming for LiveView

For event-driven architectures like Phoenix LiveView, wrap `stream/3` in a Task:

```elixir
# Start streaming in a Task and forward messages
parent = self()
Task.start(fn ->
  session
  |> ClaudeCode.stream("Tell me a story", include_partial_messages: true)
  |> ClaudeCode.Stream.text_deltas()
  |> Enum.each(&send(parent, {:chunk, &1}))
  send(parent, :complete)
end)

# Handle messages in your LiveView/GenServer
def handle_info({:chunk, chunk}, socket) do
  {:noreply, assign(socket, response: socket.assigns.response <> chunk)}
end

def handle_info(:complete, socket) do
  {:noreply, assign(socket, streaming: false)}
end
```

See [Phoenix Integration](../integration/phoenix.md) for complete LiveView examples.

## Interrupting a Stream

Stop an in-progress stream with `ClaudeCode.interrupt/1`. The stream terminates cleanly — this is not an error and doesn't require rescuing:

```elixir
# Start streaming in a task
task = Task.async(fn ->
  session
  |> ClaudeCode.stream("Write a long analysis")
  |> ClaudeCode.Stream.text_content()
  |> Enum.to_list()
end)

# Stop when you've seen enough
:ok = ClaudeCode.interrupt(session)

# Stream terminates without a result message
partial_text = Task.await(task)
```

This is useful for saving tokens when Claude is going in a direction you don't want.

## Error Handling

Streams throw on infrastructure errors. Use `catch` to handle them:

```elixir
try do
  session
  |> ClaudeCode.stream(prompt)
  |> ClaudeCode.Stream.text_content()
  |> Enum.each(&IO.write/1)
catch
  {:stream_init_error, reason} -> IO.puts("Init error: #{inspect(reason)}")
  {:stream_error, reason} -> IO.puts("Stream error: #{inspect(reason)}")
  {:stream_timeout, _ref} -> IO.puts("Timeout")
end
```

## Memory Efficiency

For large responses, process chunks immediately instead of accumulating:

```elixir
# Good: Process immediately
session
|> ClaudeCode.stream(prompt)
|> ClaudeCode.Stream.text_content()
|> Elixir.Stream.each(&IO.write/1)
|> Elixir.Stream.run()

# Avoid: Accumulating all chunks
chunks =
  session
  |> ClaudeCode.stream(prompt)
  |> ClaudeCode.Stream.text_content()
  |> Enum.to_list()  # Loads everything into memory
```

## Next Steps

- [Phoenix Integration](../integration/phoenix.md) - LiveView streaming
- [Sessions Guide](sessions.md) - Multi-turn conversations
- [Examples](../reference/examples.md) - More patterns
