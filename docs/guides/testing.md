# Testing Guide

ClaudeCode provides a test adapter that lets you mock Claude responses without making real API calls. This enables fast, deterministic tests for applications built on ClaudeCode.

## Setup

### 1. Add Test Configuration

Configure the test adapter in your test environment:

```elixir
# config/test.exs
config :claude_code, adapter: {ClaudeCode.Test, ClaudeCode.Session}
```

### 2. Start the Ownership Server

Add ClaudeCode.Test to your test helper:

```elixir
# test/test_helper.exs
ExUnit.start()
Supervisor.start_link([ClaudeCode.Test], strategy: :one_for_one)
```

### 3. Register Stubs in Tests

```elixir
test "returns greeting" do
  ClaudeCode.Test.stub(ClaudeCode.Session, fn _query, _opts ->
    [
      ClaudeCode.Test.text("Hello! How can I help?")
    ]
  end)

  {:ok, session} = ClaudeCode.start_link()
  result = session |> ClaudeCode.stream("Hi") |> ClaudeCode.Stream.final_text()
  assert result == "Hello! How can I help?"
end
```

## Message Helpers

`ClaudeCode.Test` provides helpers to construct realistic Claude messages:

| Helper | Description |
|--------|-------------|
| `text/2` | Assistant message with text content |
| `tool_use/3` | Assistant message with tool invocation |
| `tool_result/2` | User message with tool execution result |
| `thinking/2` | Assistant message with thinking block |
| `result/2` | Final result message |
| `system/1` | System initialization message |

### Text Messages

```elixir
# Simple text response
ClaudeCode.Test.text("Hello world!")

# With options
ClaudeCode.Test.text("Done", stop_reason: :end_turn)
```

### Tool Use

```elixir
# Tool invocation
ClaudeCode.Test.tool_use("Read", %{file_path: "/tmp/file.txt"})

# With preceding text
ClaudeCode.Test.tool_use("Bash", %{command: "ls -la"}, text: "Let me check the directory...")
```

### Tool Results

```elixir
# Successful tool result
ClaudeCode.Test.tool_result("file contents here")

# Failed tool result
ClaudeCode.Test.tool_result("Permission denied", is_error: true)
```

### Thinking Blocks

```elixir
# Extended thinking
ClaudeCode.Test.thinking("Let me analyze step by step...")

# Thinking followed by response
ClaudeCode.Test.thinking("First I need to...", text: "Here's my answer")
```

### Result Messages

```elixir
# Default success result
ClaudeCode.Test.result()

# Custom result
ClaudeCode.Test.result("Task completed successfully")

# Error result
ClaudeCode.Test.result("Rate limit exceeded", is_error: true)
```

## Dynamic Stubs

Stubs can be functions that receive the query and options:

```elixir
ClaudeCode.Test.stub(ClaudeCode.Session, fn query, opts ->
  cond do
    String.contains?(query, "error") ->
      [ClaudeCode.Test.result("Something went wrong", is_error: true)]

    String.contains?(query, "file") ->
      [
        ClaudeCode.Test.tool_use("Read", %{file_path: "/tmp/test.txt"}),
        ClaudeCode.Test.tool_result("file contents"),
        ClaudeCode.Test.text("I read the file"),
        ClaudeCode.Test.result()
      ]

    true ->
      [ClaudeCode.Test.text("Default response")]
  end
end)
```

## Testing Tool Sequences

Simulate multi-step tool interactions:

```elixir
test "handles file read and edit sequence" do
  ClaudeCode.Test.stub(ClaudeCode.Session, fn _query, _opts ->
    [
      ClaudeCode.Test.text("I'll read the file first"),
      ClaudeCode.Test.tool_use("Read", %{file_path: "lib/app.ex"}),
      ClaudeCode.Test.tool_result("defmodule App do\nend"),
      ClaudeCode.Test.text("Now I'll edit it"),
      ClaudeCode.Test.tool_use("Edit", %{
        file_path: "lib/app.ex",
        old_string: "defmodule App do",
        new_string: "defmodule MyApp do"
      }),
      ClaudeCode.Test.tool_result("File updated"),
      ClaudeCode.Test.text("Done! I renamed the module."),
      ClaudeCode.Test.result("Done! I renamed the module.")
    ]
  end)

  {:ok, session} = ClaudeCode.start_link()

  summary = session
  |> ClaudeCode.stream("Rename the module")
  |> ClaudeCode.Stream.collect()

  assert length(summary.tool_calls) == 2
  assert summary.result == "Done! I renamed the module."
end
```

## Concurrent Tests

`ClaudeCode.Test` uses `NimbleOwnership` for process-based isolation. Each test process owns its stubs, allowing concurrent test execution with `async: true`:

```elixir
defmodule MyAppTest do
  use ExUnit.Case, async: true

  test "concurrent test 1" do
    ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ ->
      [ClaudeCode.Test.text("Response 1")]
    end)
    # ...
  end

  test "concurrent test 2" do
    ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ ->
      [ClaudeCode.Test.text("Response 2")]
    end)
    # ...
  end
end
```

### Allowing Spawned Processes

If your test spawns processes that need stub access:

```elixir
test "spawned process can use stub" do
  ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ ->
    [ClaudeCode.Test.text("Hello")]
  end)

  task = Task.async(fn ->
    {:ok, session} = ClaudeCode.start_link()
    ClaudeCode.stream(session, "hi") |> Enum.to_list()
  end)

  # Allow the task to access our stubs
  ClaudeCode.Test.allow(ClaudeCode.Session, self(), task.pid)

  messages = Task.await(task)
  assert length(messages) > 0
end
```

### Shared Mode

For complex scenarios where process ownership is difficult to track:

```elixir
setup do
  ClaudeCode.Test.set_mode_to_shared()
  :ok
end
```

In shared mode, all processes can access stubs without explicit allowances.

## Testing with Tool Callbacks

Test your tool callback handlers:

```elixir
test "tool callback receives events" do
  events = []

  callback = fn event ->
    send(self(), {:tool_event, event})
    :ok
  end

  ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ ->
    [
      ClaudeCode.Test.tool_use("Bash", %{command: "echo hi"}),
      ClaudeCode.Test.tool_result("hi"),
      ClaudeCode.Test.result()
    ]
  end)

  {:ok, session} = ClaudeCode.start_link(tool_callback: callback)
  session |> ClaudeCode.stream("run echo") |> Stream.run()

  assert_received {:tool_event, {:tool_start, _}}
  assert_received {:tool_event, {:tool_end, _, _}}
end
```

## Auto-Generated Messages

`ClaudeCode.Test` automatically:

- **Prepends a system message** if none is provided
- **Appends a result message** if none is provided
- **Links tool_use IDs** to subsequent tool_result messages
- **Unifies session IDs** across all messages

This means minimal stubs work correctly:

```elixir
# This minimal stub works - system and result are auto-added
ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ ->
  [ClaudeCode.Test.text("Hello")]
end)
```

## Common Patterns

### Testing Error Handling

```elixir
test "handles API errors gracefully" do
  ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ ->
    [ClaudeCode.Test.result("Rate limit exceeded", is_error: true)]
  end)

  {:ok, session} = ClaudeCode.start_link()

  result = session
  |> ClaudeCode.stream("test")
  |> Enum.find(&match?(%ClaudeCode.Message.ResultMessage{}, &1))

  assert result.is_error == true
end
```

### Testing Stream Processing

```elixir
test "processes streaming text correctly" do
  ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ ->
    [
      ClaudeCode.Test.text("Part 1"),
      ClaudeCode.Test.text("Part 2"),
      ClaudeCode.Test.text("Part 3")
    ]
  end)

  {:ok, session} = ClaudeCode.start_link()

  texts = session
  |> ClaudeCode.stream("test")
  |> ClaudeCode.Stream.text_content()
  |> Enum.to_list()

  assert texts == ["Part 1", "Part 2", "Part 3"]
end
```

### Testing Multi-Turn Conversations

```elixir
test "maintains context across turns" do
  counter = :counters.new(1, [])

  ClaudeCode.Test.stub(ClaudeCode.Session, fn query, _opts ->
    :counters.add(counter, 1, 1)
    turn = :counters.get(counter, 1)

    [ClaudeCode.Test.text("Turn #{turn}: #{query}")]
  end)

  {:ok, session} = ClaudeCode.start_link()

  r1 = session |> ClaudeCode.stream("First") |> ClaudeCode.Stream.final_text()
  r2 = session |> ClaudeCode.stream("Second") |> ClaudeCode.Stream.final_text()

  assert r1 == "Turn 1: First"
  assert r2 == "Turn 2: Second"
end
```
