#!/usr/bin/env elixir
# Example of using character-level streaming for real-time output
#
# This demonstrates the `include_partial_messages: true` option which enables
# character-by-character streaming from Claude's responses - perfect for
# building responsive chat interfaces and LiveView applications.

# Start a session
{:ok, session} = ClaudeCode.start_link()

IO.puts("Example 1: Basic Character Streaming")
IO.puts("=" |> String.duplicate(60))
IO.puts("Watch the text appear character by character:\n")

session
|> ClaudeCode.stream("Count from 1 to 5, spelling out each number", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Stream.each(&IO.write/1)
|> Stream.run()

IO.puts("\n\n")

IO.puts("Example 2: Comparing Complete vs Partial Message Streaming")
IO.puts("=" |> String.duplicate(60))

IO.puts("\nWith include_partial_messages: false (default):")
IO.puts("Each chunk is a complete message:\n")

session
|> ClaudeCode.stream("Say 'Hello World'")
|> ClaudeCode.Stream.text_content()
|> Stream.each(fn chunk ->
  IO.puts("[chunk: #{inspect(chunk)}]")
end)
|> Stream.run()

IO.puts("\nWith include_partial_messages: true:")
IO.puts("Each chunk is a character/token:\n")

session
|> ClaudeCode.stream("Say 'Hello World'", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Stream.each(fn chunk ->
  IO.puts("[delta: #{inspect(chunk)}]")
end)
|> Stream.run()

IO.puts("\n")

IO.puts("Example 3: Working with Content Deltas")
IO.puts("=" |> String.duplicate(60))
IO.puts("Content deltas include index and type information:\n")

session
|> ClaudeCode.stream("Hi there!", include_partial_messages: true)
|> ClaudeCode.Stream.content_deltas()
|> Stream.each(fn delta ->
  IO.inspect(delta, label: "delta")
end)
|> Stream.run()

IO.puts("\n")

IO.puts("Example 4: Filtering Stream Events by Type")
IO.puts("=" |> String.duplicate(60))
IO.puts("Different event types during streaming:\n")

alias ClaudeCode.Message.StreamEvent

session
|> ClaudeCode.stream("Hello", include_partial_messages: true)
|> Stream.filter(&match?(%StreamEvent{}, &1))
|> Stream.each(fn %StreamEvent{event: event} ->
  IO.puts("Event type: #{event.type}")
end)
|> Stream.run()

IO.puts("\n")

IO.puts("Example 5: LiveView-style PubSub Pattern")
IO.puts("=" |> String.duplicate(60))
IO.puts("Simulating how you'd use this with Phoenix PubSub:\n")

# Simulate a PubSub broadcast (in real app, use Phoenix.PubSub)
defmodule FakePubSub do
  def broadcast(topic, message) do
    IO.puts("  [PubSub #{topic}] #{inspect(message)}")
  end
end

session_id = "chat:12345"

session
|> ClaudeCode.stream("Say hi", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Stream.each(fn text_chunk ->
  # In a real app: Phoenix.PubSub.broadcast(MyApp.PubSub, topic, message)
  FakePubSub.broadcast(session_id, {:text_chunk, text_chunk})
end)
|> Stream.run()

IO.puts("\n")

IO.puts("Example 6: Accumulating Text with Real-time Display")
IO.puts("=" |> String.duplicate(60))
IO.puts("Building up the full response while streaming:\n")

{chunks, final_text} =
  session
  |> ClaudeCode.stream("List three colors", include_partial_messages: true)
  |> ClaudeCode.Stream.text_deltas()
  |> Enum.reduce({[], ""}, fn chunk, {chunks, acc} ->
    IO.write(chunk)
    {[chunk | chunks], acc <> chunk}
  end)

IO.puts("\n\nReceived #{length(chunks)} chunks")
IO.puts("Final text length: #{String.length(final_text)} characters")

IO.puts("\n")

IO.puts("Example 7: Timing Analysis")
IO.puts("=" |> String.duplicate(60))
IO.puts("Measuring time-to-first-token:\n")

start_time = System.monotonic_time(:millisecond)
first_chunk_time = nil

session
|> ClaudeCode.stream("Write a haiku", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Stream.with_index()
|> Stream.each(fn {chunk, index} ->
  current_time = System.monotonic_time(:millisecond)

  if index == 0 do
    ttft = current_time - start_time
    IO.puts("[Time to first token: #{ttft}ms]")
  end

  IO.write(chunk)
end)
|> Stream.run()

total_time = System.monotonic_time(:millisecond) - start_time
IO.puts("\n[Total streaming time: #{total_time}ms]")

# Clean up
ClaudeCode.stop(session)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Character streaming examples complete!")
