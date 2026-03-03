#!/usr/bin/env elixir
# Example of using character-level streaming for real-time output
#
# This demonstrates the `include_partial_messages: true` option which enables
# character-by-character streaming from Claude's responses - perfect for
# building responsive chat interfaces and LiveView applications.

alias ClaudeCode.Message.PartialAssistantMessage

# Partial message streaming is configured when the CLI session starts.
{:ok, standard_session} = ClaudeCode.start_link()
{:ok, partial_session} = ClaudeCode.start_link(include_partial_messages: true)

IO.puts("Example 1: Basic Character Streaming")
"=" |> String.duplicate(60) |> IO.puts()
IO.puts("Watch the text appear character by character:\n")

partial_session
|> ClaudeCode.stream("Count from 1 to 5, spelling out each number")
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(&IO.write/1)

IO.puts("\n\n")

IO.puts("Example 2: Comparing Complete vs Partial Message Streaming")
"=" |> String.duplicate(60) |> IO.puts()

IO.puts("\nWith include_partial_messages: false (default):")
IO.puts("Each chunk is a complete message:\n")

standard_session
|> ClaudeCode.stream("Say 'Hello World'")
|> ClaudeCode.Stream.text_content()
|> Enum.each(fn chunk ->
  IO.puts("[chunk: #{inspect(chunk)}]")
end)

IO.puts("\nWith include_partial_messages: true:")
IO.puts("Each chunk is a character/token:\n")

partial_session
|> ClaudeCode.stream("Say 'Hello World'")
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(fn chunk ->
  IO.puts("[delta: #{inspect(chunk)}]")
end)

IO.puts("\n")

IO.puts("Example 3: Working with Content Deltas")
"=" |> String.duplicate(60) |> IO.puts()
IO.puts("Content deltas include index and type information:\n")

partial_session
|> ClaudeCode.stream("Hi there!")
|> ClaudeCode.Stream.content_deltas()
|> Enum.each(fn delta ->
  IO.inspect(delta, label: "delta")
end)

IO.puts("\n")

IO.puts("Example 4: Filtering Stream Events by Type")
"=" |> String.duplicate(60) |> IO.puts()
IO.puts("Different event types during streaming:\n")

partial_session
|> ClaudeCode.stream("Hello")
|> Stream.filter(&match?(%PartialAssistantMessage{}, &1))
|> Enum.each(fn %PartialAssistantMessage{event: event} ->
  IO.puts("Event type: #{event.type}")
end)

IO.puts("\n")

IO.puts("Example 5: LiveView-style PubSub Pattern")
"=" |> String.duplicate(60) |> IO.puts()
IO.puts("Simulating how you'd use this with Phoenix PubSub:\n")

# Simulate a PubSub broadcast (in real app, use Phoenix.PubSub)
defmodule FakePubSub do
  @moduledoc false
  def broadcast(topic, message) do
    IO.puts("  [PubSub #{topic}] #{inspect(message)}")
  end
end

session_id = "chat:12345"

partial_session
|> ClaudeCode.stream("Say hi")
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(fn text_chunk ->
  # In a real app: Phoenix.PubSub.broadcast(MyApp.PubSub, topic, message)
  FakePubSub.broadcast(session_id, {:text_chunk, text_chunk})
end)

IO.puts("\n")

IO.puts("Example 6: Accumulating Text with Real-time Display")
"=" |> String.duplicate(60) |> IO.puts()
IO.puts("Building up the full response while streaming:\n")

{chunks, final_text} =
  partial_session
  |> ClaudeCode.stream("List three colors")
  |> ClaudeCode.Stream.text_deltas()
  |> Enum.reduce({[], ""}, fn chunk, {chunks, acc} ->
    IO.write(chunk)
    {[chunk | chunks], acc <> chunk}
  end)

IO.puts("\n\nReceived #{length(chunks)} chunks")
IO.puts("Final text length: #{String.length(final_text)} characters")

IO.puts("\n")

IO.puts("Example 7: Timing Analysis")
"=" |> String.duplicate(60) |> IO.puts()
IO.puts("Measuring time-to-first-token:\n")

start_time = System.monotonic_time(:millisecond)

partial_session
|> ClaudeCode.stream("Write a haiku")
|> ClaudeCode.Stream.text_deltas()
|> Stream.with_index()
|> Enum.each(fn {chunk, index} ->
  current_time = System.monotonic_time(:millisecond)

  if index == 0 do
    ttft = current_time - start_time
    IO.puts("[Time to first token: #{ttft}ms]")
  end

  IO.write(chunk)
end)

total_time = System.monotonic_time(:millisecond) - start_time
IO.puts("\n[Total streaming time: #{total_time}ms]")

# Clean up
ClaudeCode.stop(standard_session)
ClaudeCode.stop(partial_session)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Character streaming examples complete!")
