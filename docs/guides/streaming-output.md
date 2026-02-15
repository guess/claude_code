# Streaming Output

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/streaming-output). Examples are adapted for Elixir.

Get real-time responses from the Agent SDK as text and tool calls stream in.

---

By default, the SDK yields complete `AssistantMessage` structs after Claude finishes generating each response. To receive incremental updates as text and tool calls are generated, enable partial message streaming by setting `include_partial_messages: true` in your options.

> **Tip:** This page covers output streaming (receiving tokens in real-time). For input modes (how you send messages), see [Streaming vs Single Mode](streaming-vs-single-mode.md). You can also [stream responses using the Agent SDK via the CLI](https://code.claude.com/docs/en/headless).

## Enable streaming output

To enable streaming, set `include_partial_messages: true` in your options. This causes the SDK to yield `PartialAssistantMessage` structs containing raw API events as they arrive, in addition to the usual `AssistantMessage` and `ResultMessage`.

Your code then needs to:

1. Check each message's type to distinguish `PartialAssistantMessage` from other message types
2. For `PartialAssistantMessage`, extract the `event` field and check its `type`
3. Look for `:content_block_delta` events where the delta type is `:text_delta`, which contain the actual text chunks

The example below enables streaming and prints text chunks as they arrive. Notice the nested pattern matching: first for `PartialAssistantMessage`, then for `:content_block_delta`, then for `:text_delta`:

```elixir
{:ok, session} = ClaudeCode.start_link(
  include_partial_messages: true,
  allowed_tools: ["Bash", "Read"]
)

session
|> ClaudeCode.stream("List the files in my project")
|> Enum.each(fn
  %{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}} ->
    IO.write(text)

  _ ->
    :ok
end)
```

Or use the convenience function:

```elixir
session
|> ClaudeCode.stream("List the files in my project", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(&IO.write/1)
```

## PartialAssistantMessage reference

When partial messages are enabled, you receive raw Claude API streaming events wrapped in a `PartialAssistantMessage` struct. This corresponds to `StreamEvent` in Python and `SDKPartialAssistantMessage` in TypeScript. These contain raw Claude API events, not accumulated text. You need to extract and accumulate text deltas yourself (or use the convenience functions in `ClaudeCode.Stream`).

```elixir
%ClaudeCode.Message.PartialAssistantMessage{
  type: :stream_event,                  # Always :stream_event
  event: %{type: event_type, ...},      # The raw Claude API stream event
  session_id: "session_id",             # Session identifier
  parent_tool_use_id: nil,              # Parent tool ID if from a subagent
  uuid: "uuid"                          # Unique identifier for this event
}
```

The `event` field contains the raw streaming event from the [Claude API](https://platform.claude.com/docs/en/build-with-claude/streaming#event-types). Common event types include:

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

Without partial messages enabled, you receive all message types except `PartialAssistantMessage`. Common types include `SystemMessage` (session initialization), `AssistantMessage` (complete responses), `ResultMessage` (final result), and `CompactBoundaryMessage` (indicates when conversation history was compacted).

## Stream text responses

To display text as it's generated, look for `:content_block_delta` events where the delta type is `:text_delta`. These contain the incremental text chunks:

```elixir
{:ok, session} = ClaudeCode.start_link(include_partial_messages: true)

session
|> ClaudeCode.stream("Explain how databases work")
|> Enum.each(fn
  %{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}} ->
    IO.write(text)

  _ ->
    :ok
end)
```

Or use the convenience function:

```elixir
session
|> ClaudeCode.stream("Explain how databases work", include_partial_messages: true)
|> ClaudeCode.Stream.text_deltas()
|> Enum.each(&IO.write/1)
```

## Stream tool calls

Tool calls also stream incrementally. You can track when tools start, receive their input as it's generated, and see when they complete. The example below tracks the current tool being called and accumulates the JSON input as it streams in. It uses three event types:

- `:content_block_start` -- tool begins
- `:content_block_delta` with `:input_json_delta` -- input chunks arrive
- `:content_block_stop` -- tool call complete

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

  %{event: %{type: :content_block_delta, delta: %{type: :input_json_delta, partial_json: chunk}}}, {tool, input} ->
    {tool, input <> chunk}

  %{event: %{type: :content_block_stop}}, {tool, input} when tool != nil ->
    IO.puts("Tool #{tool} called with: #{input}")
    {nil, ""}

  _, acc ->
    acc
end)
```

## Build a streaming UI

This example combines text and tool streaming into a cohesive UI. It tracks whether the agent is currently executing a tool (using an `in_tool` flag) to show status indicators like `[Using Read...]` while tools run. Text streams normally when not in a tool, and tool completion triggers a "done" message. This pattern is useful for chat interfaces that need to show progress during multi-step agent tasks.

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

  %{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}}, false ->
    IO.write(text)
    false

  %{event: %{type: :content_block_stop}}, true ->
    IO.puts(" done")
    false

  %ClaudeCode.Message.ResultMessage{}, _ ->
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

Some SDK features are incompatible with streaming:

- **Extended thinking**: when you explicitly set `max_thinking_tokens` (or `thinking: {:enabled, budget_tokens: n}`), `PartialAssistantMessage` events are not emitted. You'll only receive complete messages after each turn. Note that thinking is disabled by default in the SDK, so streaming works unless you enable it.
- **Structured output**: the JSON result appears only in the final `ResultMessage`, not as streaming deltas. See [Structured Outputs](structured-outputs.md) for details.

## Next steps

Now that you can stream text and tool calls in real-time, explore these related topics:

- [Streaming vs Single Mode](streaming-vs-single-mode.md) - Choose between input modes for your use case
- [Structured Outputs](structured-outputs.md) - Get typed JSON responses from the agent
- [Permissions](permissions.md) - Control which tools the agent can use
