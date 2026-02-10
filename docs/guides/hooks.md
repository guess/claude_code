# Hooks

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hooks). Examples are adapted for Elixir.

⚠️ TODO: THIS FEATURE IS INCOMPLETE

Monitor and audit tool execution with the `tool_callback` option.

## Tool Callback

The `tool_callback` option receives a notification after each tool execution completes:

```elixir
{:ok, session} = ClaudeCode.start_link(
  tool_callback: fn event ->
    IO.puts("[#{event.name}] #{if event.is_error, do: "FAILED", else: "OK"}")
  end
)

session
|> ClaudeCode.stream("Create a hello.txt file with 'Hello World'")
|> ClaudeCode.Stream.final_text()
```

Output:

```
[Write] OK
```

## Event Structure

The callback receives a map with these fields:

| Field          | Type           | Description                                     |
| -------------- | -------------- | ----------------------------------------------- |
| `:name`        | `String.t()`   | Tool name (e.g., `"Read"`, `"Write"`, `"Bash"`) |
| `:input`       | `map()`        | Tool input parameters                           |
| `:result`      | `String.t()`   | Tool execution output                           |
| `:is_error`    | `boolean()`    | Whether the tool errored                        |
| `:tool_use_id` | `String.t()`   | Unique ID for correlating use/result pairs      |
| `:timestamp`   | `DateTime.t()` | When the result was received                    |

## Logging Example

```elixir
callback = fn event ->
  Logger.info("""
  Tool Execution:
    Tool: #{event.name}
    Input: #{inspect(event.input)}
    Error: #{event.is_error}
    Result: #{String.slice(event.result || "", 0, 200)}
  """)
end

{:ok, session} = ClaudeCode.start_link(tool_callback: callback)
```

## Auditing to a Database

```elixir
callback = fn event ->
  MyApp.AuditLog.insert(%{
    tool_name: event.name,
    tool_input: event.input,
    tool_result: event.result,
    is_error: event.is_error,
    tool_use_id: event.tool_use_id,
    executed_at: event.timestamp
  })
end

{:ok, session} = ClaudeCode.start_link(tool_callback: callback)
```

## Metrics Collection

```elixir
callback = fn event ->
  :telemetry.execute(
    [:claude_code, :tool, :execution],
    %{duration: 1},
    %{tool: event.name, error: event.is_error}
  )
end

{:ok, session} = ClaudeCode.start_link(tool_callback: callback)
```

## In-Stream Tool Monitoring

You can also observe tool usage in real-time within a stream pipeline using `Stream.on_tool_use/2`:

```elixir
session
|> ClaudeCode.stream("Set up a new Phoenix project")
|> ClaudeCode.Stream.on_tool_use(fn tool ->
  IO.puts("  -> Using #{tool.name}")
end)
|> ClaudeCode.Stream.final_text()
```

## Important Notes

- Callbacks are invoked **asynchronously** via `Task.start/1` so they don't block message processing.
- Callbacks fire **after** tool execution, not before. You cannot block or modify tool execution.
- The callback is set at session level and applies to all queries on that session.

## CLI Hooks vs SDK Callbacks

The Claude Code CLI supports a separate hooks system (`PreToolUse`, `PostToolUse`, etc.) configured via `.claude/hooks.json`. These are different from the SDK's `tool_callback`:

| Feature       | SDK `tool_callback` | CLI Hooks                   |
| ------------- | ------------------- | --------------------------- |
| When          | Post-execution only | Pre and post execution      |
| Can block?    | No                  | Yes (PreToolUse can reject) |
| Configuration | Elixir code         | JSON config file            |
| Scope         | Per-session         | Per-project/user            |

To use CLI hooks alongside the SDK, configure them in your project's `.claude/hooks.json`. They will be respected by the CLI subprocess.

## Next Steps

- [Sessions](sessions.md) - Session management and conversation history
- [Cost Tracking](cost-tracking.md) - Monitor API usage and costs
