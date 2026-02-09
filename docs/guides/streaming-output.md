# Streaming Output

The SDK supports real-time character-level streaming through partial messages, enabling responsive UIs and live output.

## Enabling Partial Messages

By default, the stream emits complete messages (system, assistant, user, result). To get character-by-character deltas, enable partial messages:

```elixir
{:ok, session} = ClaudeCode.start_link(include_partial_messages: true)
```

Or per-query:

```elixir
ClaudeCode.stream(session, "Tell me a story", include_partial_messages: true)
```

## Text Deltas

Stream text as it's generated, character by character:

```elixir
session
|> ClaudeCode.stream("Write a poem", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(&IO.write/1)
```

## Thinking Deltas

Stream Claude's extended thinking in real-time:

```elixir
session
|> ClaudeCode.stream("Solve this complex problem", include_partial_messages: true)
|> ClaudeCode.Stream.thinking_deltas()
|> Enum.each(&IO.write/1)
```

## Content Deltas

Get all delta types with their content block index:

```elixir
session
|> ClaudeCode.stream("Create a file", include_partial_messages: true)
|> ClaudeCode.Stream.content_deltas()
|> Enum.each(fn delta ->
  case delta.type do
    :text_delta -> IO.write(delta.text)
    :thinking_delta -> IO.write("[thinking] #{delta.thinking}")
    :input_json_delta -> IO.write("[tool input] #{delta.partial_json}")
  end
end)
```

## Filtering by Event Type

Filter the raw stream to specific event types:

```elixir
session
|> ClaudeCode.stream("Hello", include_partial_messages: true)
|> ClaudeCode.Stream.filter_event_type(:content_block_delta)
|> Enum.each(&process_delta/1)
```

Valid event types: `:message_start`, `:content_block_start`, `:content_block_delta`, `:content_block_stop`, `:message_delta`, `:message_stop`

## Message Flow

When `include_partial_messages: true`, a typical stream looks like:

```
SystemMessage (init)
PartialAssistantMessage (message_start)
PartialAssistantMessage (content_block_start, index: 0)
PartialAssistantMessage (content_block_delta, text: "H")
PartialAssistantMessage (content_block_delta, text: "el")
PartialAssistantMessage (content_block_delta, text: "lo")
PartialAssistantMessage (content_block_stop, index: 0)
PartialAssistantMessage (message_delta)
PartialAssistantMessage (message_stop)
AssistantMessage (complete message with all content)
ResultMessage (final result with usage and cost)
```

Without partial messages, you only get `SystemMessage`, `AssistantMessage`, `UserMessage`, and `ResultMessage`.

## Phoenix LiveView Integration

Stream text directly to a LiveView process:

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  def handle_event("send", %{"message" => message}, socket) do
    session = socket.assigns.session

    Task.start(fn ->
      session
      |> ClaudeCode.stream(message, include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(fn chunk ->
        send(socket.root_pid, {:text_chunk, chunk})
      end)

      send(socket.root_pid, :stream_done)
    end)

    {:noreply, socket}
  end

  def handle_info({:text_chunk, chunk}, socket) do
    {:noreply, assign(socket, response: socket.assigns.response <> chunk)}
  end

  def handle_info(:stream_done, socket) do
    {:noreply, assign(socket, streaming: false)}
  end
end
```

Or using PubSub for multi-subscriber broadcasting:

```elixir
session
|> ClaudeCode.stream("Generate report", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(fn chunk ->
  Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:#{chat_id}", {:text_chunk, chunk})
end)
```

## Stream Utilities Reference

| Function | Input | Output |
|----------|-------|--------|
| `text_deltas/1` | stream with partials | text character chunks |
| `thinking_deltas/1` | stream with partials | thinking character chunks |
| `content_deltas/1` | stream with partials | delta maps with type and index |
| `filter_event_type/2` | stream with partials | filtered partial messages |
| `text_content/1` | any stream | complete text strings from assistant messages |
| `thinking_content/1` | any stream | complete thinking strings |
| `tool_uses/1` | any stream | `ToolUseBlock` structs |
| `final_text/1` | any stream | single result string |
| `collect/1` | any stream | summary map with text, tool_calls, result |

## Next Steps

- [Stop Reasons](stop-reasons.md) - Understanding result message subtypes
- [Phoenix Integration](../integration/phoenix.md) - Full LiveView patterns
