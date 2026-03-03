#!/usr/bin/env elixir
# Example of using the ClaudeCode streaming API

alias ClaudeCode.Message.AssistantMessage
alias ClaudeCode.Message.ResultMessage

# Start a session
{:ok, session} = ClaudeCode.start_link()

IO.puts("Example 1: Using Stream.text_content() helper (recommended)")
"=" |> String.duplicate(60) |> IO.puts()

session
|> ClaudeCode.stream("Explain GenServers in Elixir in 2 sentences")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

IO.puts("\n\n")

IO.puts("Example 2: Working with raw messages")
"=" |> String.duplicate(60) |> IO.puts()

session
|> ClaudeCode.stream("What is pattern matching?")
|> Enum.each(fn message ->
  case message do
    %AssistantMessage{message: %{content: content}} ->
      # Extract text from content blocks
      Enum.each(content, fn
        %ClaudeCode.Content.TextBlock{text: text} -> IO.write(text)
        _ -> :ok
      end)

    %ResultMessage{result: result} ->
      IO.puts("\n\nFinal result: #{result}")

    _ ->
      :ok
  end
end)

IO.puts("\n")

IO.puts("Example 3: Filtering for specific message types")
"=" |> String.duplicate(60) |> IO.puts()

# Collect only assistant messages
messages =
  session
  |> ClaudeCode.stream("List 3 Elixir features")
  |> ClaudeCode.Stream.filter_type(:assistant)
  |> Enum.to_list()

IO.puts("Received #{length(messages)} assistant messages")

IO.puts("\n")

IO.puts("Example 4: Using Stream.final_text() for one-shot output")
"=" |> String.duplicate(60) |> IO.puts()

final_text =
  session
  |> ClaudeCode.stream("Tell me about OTP")
  |> ClaudeCode.Stream.final_text()

IO.puts(final_text || "[no final text received]")

# Clean up
ClaudeCode.stop(session)
