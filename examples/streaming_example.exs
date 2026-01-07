#!/usr/bin/env elixir
# Example of using the ClaudeCode streaming API

# Start a session
{:ok, session} = ClaudeCode.start_link(api_key: System.get_env("ANTHROPIC_API_KEY"))

IO.puts("Example 1: Using Stream.text_content() helper (recommended)")
IO.puts("=" |> String.duplicate(60))

session
|> ClaudeCode.stream("Explain GenServers in Elixir in 2 sentences")
|> ClaudeCode.Stream.text_content()
|> Stream.each(&IO.write/1)
|> Stream.run()

IO.puts("\n\n")

IO.puts("Example 2: Working with raw messages")
IO.puts("=" |> String.duplicate(60))

session
|> ClaudeCode.stream("What is pattern matching?")
|> Stream.each(fn message ->
  case message do
    %ClaudeCode.Message.Assistant{message: %{content: content}} ->
      # Extract text from content blocks
      Enum.each(content, fn
        %ClaudeCode.Content.TextBlock{text: text} -> IO.write(text)
        _ -> :ok
      end)

    %ClaudeCode.Message.Result{result: result} ->
      IO.puts("\n\nFinal result: #{result}")

    _ ->
      :ok
  end
end)
|> Stream.run()

IO.puts("\n")

IO.puts("Example 3: Filtering for specific message types")
IO.puts("=" |> String.duplicate(60))

# Collect only assistant messages
messages =
  session
  |> ClaudeCode.stream("List 3 Elixir features")
  |> ClaudeCode.Stream.filter_type(:assistant)
  |> Enum.to_list()

IO.puts("Received #{length(messages)} assistant messages")

IO.puts("\n")

IO.puts("Example 4: Using buffered text for complete sentences")
IO.puts("=" |> String.duplicate(60))

session
|> ClaudeCode.stream("Tell me about OTP")
|> ClaudeCode.Stream.buffered_text()
|> Stream.each(&IO.puts/1)
|> Stream.run()

# Clean up
ClaudeCode.stop(session)
