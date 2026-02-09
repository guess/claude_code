# Stream Responses in Real-time

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/streaming-output). Examples are adapted for Elixir.

Get real-time responses from the Agent SDK as text and tool calls stream in.

---

By default, the SDK yields complete `AssistantMessage` structs after Claude finishes generating each response. To receive incremental updates as text and tool calls are generated, enable partial message streaming by setting `include_partial_messages: true` in your options.

> **Tip:** This page covers output streaming (receiving tokens in real-time). For input modes (how you send messages), see [Streaming vs Single Mode](streaming-vs-single-mode.md).

## Stream text responses

Set `include_partial_messages: true`, then pattern match on the `event` field to extract text chunks as they arrive:

```elixir
{:ok, session} = ClaudeCode.start_link(include_partial_messages: true)

session
|> ClaudeCode.stream("Explain how databases work")
|> Enum.each(fn
  %{event: %{delta: %{type: :text_delta, text: text}}} -> IO.write(text)
  _ -> :ok
end)
```

Or use the convenience function:

```elixir
session
|> ClaudeCode.stream("Explain how databases work", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(&IO.write/1)
```

## PartialAssistantMessage reference

When partial messages are enabled, you receive raw Claude API streaming events wrapped in a `PartialAssistantMessage` struct. This corresponds to `StreamEvent` in Python and `SDKPartialAssistantMessage` in TypeScript.

```elixir
%ClaudeCode.Message.PartialAssistantMessage{
  type: :stream_event,                  # Always :stream_event
  event: %{type: event_type, ...},      # The raw Claude API stream event
  session_id: "session_id",             # Session identifier
  parent_tool_use_id: nil,              # Parent tool ID if from a subagent
  uuid: "uuid"                          # Unique identifier for this event
}
```

Common event types in the `event` field:

| Event Type | Description |
|:-----------|:------------|
| `:message_start` | Start of a new message |
| `:content_block_start` | Start of a new content block (text or tool use) |
| `:content_block_delta` | Incremental update to content |
| `:content_block_stop` | End of a content block |
| `:message_delta` | Message-level updates (stop reason, usage) |
| `:message_stop` | End of the message |

## Message flow

With partial messages enabled, you receive messages in this order:

```
PartialAssistantMessage (message_start)
PartialAssistantMessage (content_block_start) - text block
PartialAssistantMessage (content_block_delta) - text chunks...
PartialAssistantMessage (content_block_stop)
PartialAssistantMessage (content_block_start) - tool_use block
PartialAssistantMessage (content_block_delta) - tool input chunks...
PartialAssistantMessage (content_block_stop)
PartialAssistantMessage (message_delta)
PartialAssistantMessage (message_stop)
AssistantMessage - complete message with all content
... tool executes ...
... more streaming events for next turn ...
ResultMessage - final result
```

Without partial messages, you receive all message types except `PartialAssistantMessage`: `SystemMessage` (session initialization), `AssistantMessage` (complete responses), `ResultMessage` (final result), and `CompactBoundaryMessage` (context compaction).

## Stream tool calls

Tool calls also stream incrementally. Track when tools start, receive their input as it's generated, and see when they complete:

```elixir
{:ok, session} = ClaudeCode.start_link(
  include_partial_messages: true,
  allowed_tools: ["Read", "Bash"]
)

session
|> ClaudeCode.stream("Read the README.md file")
|> Enum.reduce({nil, ""}, fn
  %{event: %{type: :content_block_start, content_block: %{type: :tool_use, name: name}}}, _ ->
    IO.puts("Starting tool: #{name}")
    {name, ""}

  %{event: %{delta: %{type: :input_json_delta, partial_json: chunk}}}, {tool, input} ->
    {tool, input <> chunk}

  %{event: %{type: :content_block_stop}}, {tool, input} when tool != nil ->
    IO.puts("Tool #{tool} called with: #{input}")
    {nil, ""}

  _, acc ->
    acc
end)
```

## Build a streaming UI

Combine text and tool streaming into a cohesive UI. This tracks whether a tool is executing to show status indicators like `[Using Read...]` while tools run, and streams text normally otherwise:

```elixir
{:ok, session} = ClaudeCode.start_link(
  include_partial_messages: true,
  allowed_tools: ["Read", "Bash", "Grep"]
)

session
|> ClaudeCode.stream("Find all TODO comments in the codebase")
|> Enum.reduce(_in_tool = false, fn
  %{event: %{type: :content_block_start, content_block: %{type: :tool_use, name: name}}}, _ ->
    IO.write("\n[Using #{name}...]")
    true

  %{event: %{delta: %{type: :text_delta, text: text}}}, false ->
    IO.write(text)
    false

  %{event: %{type: :content_block_stop}}, true ->
    IO.puts(" done")
    false

  %{type: :result}, _ ->
    IO.puts("\n\n--- Complete ---")
    false

  _, in_tool ->
    in_tool
end)
```

## Phoenix LiveView integration

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
      |> Enum.each(&send(socket.root_pid, {:text_chunk, &1}))

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

For multi-subscriber broadcasting, use PubSub:

```elixir
session
|> ClaudeCode.stream("Generate report", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(&Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:#{chat_id}", {:text_chunk, &1}))
```

## Convenience functions

The Elixir SDK provides high-level stream utilities that handle the pattern matching shown above.

**Partial message streams** (`include_partial_messages: true`):

| Function | Description |
|:---------|:------------|
| `text_deltas/1` | Extracts text chunks from `:text_delta` events |
| `thinking_deltas/1` | Extracts thinking chunks from `:thinking_delta` events |
| `content_deltas/1` | All delta types with index (text, tool input, thinking) |
| `filter_event_type/2` | Filter to a specific event type (e.g., `:content_block_start`) |

**Complete message streams** (no `include_partial_messages` required):

| Function | Description |
|:---------|:------------|
| `text_content/1` | Complete text strings from assistant messages |
| `thinking_content/1` | Complete thinking strings from assistant messages |
| `tool_uses/1` | `ToolUseBlock` structs from assistant messages |
| `final_text/1` | Single result string (consumes stream) |
| `collect/1` | Summary map with text, tool_calls, thinking, result |
| `on_tool_use/2` | Side-effect callback when tools are used |

## Known limitations

- **Extended thinking**: when you set `max_thinking_tokens`, `PartialAssistantMessage` events are not emitted. You'll only receive complete messages after each turn. Thinking is disabled by default, so streaming works unless you enable it.
- **Structured output**: the JSON result appears only in the final `ResultMessage`, not as streaming deltas. See [Structured Outputs](structured-outputs.md) for details.

## Next steps

- [Streaming vs Single Mode](streaming-vs-single-mode.md) - Choose between input modes
- [Structured Outputs](structured-outputs.md) - Get typed JSON responses
- [Permissions](permissions.md) - Control which tools the agent can use
