# P1: Streaming and Session Forking

**Status**: High Priority - Required for v1.0
**Effort**: ~8 hours
**Priority**: Complete in Week 2

## Objective

Enable real-time streaming for LiveView applications and conversation branching for complex workflows. These features complete the SDK's parity with TypeScript SDK for 95% of use cases.

## Problem

1. **No partial message streaming**: Current SDK only streams complete messages. LiveView applications need character-by-character streaming for real-time UX.

2. **No session forking**: Applications cannot branch conversations to explore different paths or implement undo/redo functionality.

## Scope

### 1. Partial Message Streaming (~5 hours)

**What**: Enable `--include-partial-messages` to stream message fragments as they arrive

**Current Behavior**:
```elixir
# Only emits complete messages
stream |> Enum.each(fn msg ->
  case msg do
    %ClaudeCode.Message.Assistant{message: %{content: [%Text{text: text}]}} ->
      IO.puts(text)  # Full response at once
  end
end)
```

**Desired Behavior**:
```elixir
# Emits partial messages for real-time display
ClaudeCode.query_stream(session, "Explain Elixir", include_partial_messages: true)
|> ClaudeCode.Stream.text_content()
|> Enum.each(fn text_chunk ->
  Phoenix.PubSub.broadcast(MyApp.PubSub, "session:#{id}", {:text_chunk, text_chunk})
end)
```

**Implementation**:
- Add `:include_partial_messages` option to schema
- Map to `--include-partial-messages` CLI flag
- Add new message type `ClaudeCode.Message.PartialAssistant`
- Update `ClaudeCode.Message.parse/1` to handle partial messages
- Add `ClaudeCode.Stream.partial_text_content/1` utility
- Update buffer logic to handle incremental text

**Files**:
- `/lib/claude_code/options.ex` - Add option
- `/lib/claude_code/message.ex` - Parse partial messages
- `/lib/claude_code/message/partial_assistant.ex` - New message type
- `/lib/claude_code/stream.ex` - Add partial text utility
- `/test/claude_code/stream_test.exs` - Test partial streaming
- `/examples/liveview_streaming.exs` - LiveView pattern

**CLI Behavior to Test**:
```bash
claude --include-partial-messages --print "Tell me a story"
# Should output incremental message_delta events
```

### 2. Session Forking (~3 hours)

**What**: Enable `--fork-session` to branch conversations

**Use Cases**:
- A/B testing different prompts
- Undo/redo functionality
- Exploring multiple solution paths
- Conversation branching in chat applications

**Implementation**:
- Add `:fork_session` option to schema
- Map to `--fork-session <session-id>` CLI flag
- Add `ClaudeCode.Session.fork/2` convenience function
- Track forked sessions in session state
- Document fork semantics

**Files**:
- `/lib/claude_code/options.ex` - Add option
- `/lib/claude_code/session.ex` - Add fork/2 function
- `/lib/claude_code/cli.ex` - Handle fork flag format
- `/test/claude_code/session_test.exs` - Test forking
- `/examples/conversation_branching.exs` - Show fork patterns

**Example Usage**:
```elixir
{:ok, original} = ClaudeCode.start_link(api_key: key)
ClaudeCode.query(original, "What is Elixir?")

# Fork to explore different paths
{:ok, branch_a} = ClaudeCode.Session.fork(original)
ClaudeCode.query(branch_a, "Tell me more about OTP")

{:ok, branch_b} = ClaudeCode.Session.fork(original)
ClaudeCode.query(branch_b, "Tell me more about Phoenix")
```

### 3. Team Settings (~optional, can defer)

**What**: Load team configuration with `--settings`

**Defer Decision**: Assess priority after completing streaming and forking. May move to v1.1 if time constrained.

## Success Criteria

- [ ] `:include_partial_messages` streams text incrementally
- [ ] Partial messages work with existing stream utilities
- [ ] LiveView example shows real-time updates
- [ ] `:fork_session` creates independent conversation branches
- [ ] Forked sessions maintain separate state
- [ ] Documentation explains streaming and forking patterns
- [ ] Test coverage >95%
- [ ] Performance benchmarked (no streaming bottlenecks)

## Dependencies

- P0: Tool Control Fixes (clean foundation)
- P0: Production Features (complete critical path first)

## Notes

**LiveView Integration**: This unlocks the killer feature for Phoenix apps - real-time AI interactions with character-by-character streaming.

**Performance Consideration**: Partial messages will significantly increase message volume. Ensure stream backpressure handling is solid.

**CLI Format Research Needed**:
- Verify `--include-partial-messages` output format
- Understand message_delta vs message_partial events
- Test with real CLI before implementing parser
