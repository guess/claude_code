# Control Execution with Hooks

Intercept, approve, and observe every tool execution in your Claude session.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hooks). Examples are adapted for Elixir.

## Overview

The SDK provides two complementary systems for controlling tool execution:

| System | Option | Purpose |
|--------|--------|---------|
| **can_use_tool** | `:can_use_tool` | Permission decisions before every tool execution |
| **Hooks** | `:hooks` | Lifecycle event callbacks (pre/post tool use, stop, compact, etc.) |

Both accept modules implementing `ClaudeCode.Hook` or anonymous functions with the same `call/2` signature. They can be used independently or together.

## can_use_tool

The `:can_use_tool` option registers a permission callback that the CLI invokes before every tool execution. Your callback decides whether to allow, deny, or modify the tool call.

### Module callback

```elixir
defmodule MyApp.ToolPermissions do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{tool_name: "Bash", input: %{"command" => cmd}}, _tool_use_id) do
    cond do
      String.contains?(cmd, "rm -rf") -> {:deny, "Destructive command blocked"}
      String.starts_with?(cmd, "sudo") -> {:deny, "No sudo allowed"}
      true -> :allow
    end
  end

  def call(_input, _tool_use_id), do: :allow
end

{:ok, session} = ClaudeCode.start_link(can_use_tool: MyApp.ToolPermissions)
```

### Anonymous function

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: fn %{tool_name: name}, _id ->
    if name in ["Read", "Glob", "Grep"], do: :allow, else: {:deny, "Read-only mode"}
  end
)
```

### Return values

| Return | Effect |
|--------|--------|
| `:allow` | Permit the tool call |
| `{:allow, updated_input}` | Permit with modified input |
| `{:allow, updated_input, permissions: updates}` | Permit with modified input and permission updates |
| `{:deny, reason}` | Block the tool call with an explanation |
| `{:deny, reason, interrupt: true}` | Block and interrupt the session |

### Input rewriting

Return `{:allow, updated_input}` to modify tool input before execution. This is useful for enforcing constraints like sandbox paths:

```elixir
defmodule MyApp.SandboxEnforcer do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{tool_name: "Write", input: %{"file_path" => path} = input}, _id) do
    if String.starts_with?(path, "/sandbox/") do
      :allow
    else
      {:allow, Map.put(input, "file_path", "/sandbox" <> path)}
    end
  end

  def call(_input, _id), do: :allow
end
```

### How it works

When `:can_use_tool` is set, the SDK automatically adds `--permission-prompt-tool stdio` to the CLI flags. The CLI sends a control request before each tool execution, and the adapter invokes your callback synchronously to get a decision.

> **Note:** `:can_use_tool` and `:permission_prompt_tool` cannot be used together. If you need programmatic tool approval, use `:can_use_tool`.

## Hooks

The `:hooks` option registers lifecycle callbacks for specific events. Unlike `:can_use_tool` (which only handles pre-execution permission), hooks cover the full tool lifecycle and session events.

### Configuration

Hooks are configured as a map of event names to lists of matcher configs:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      %{matcher: "Bash", hooks: [MyApp.BashAuditor], timeout: 30},
      %{hooks: [MyApp.GlobalLogger]}
    ],
    PostToolUse: [
      %{matcher: "Write|Edit", hooks: [MyApp.FileChangeTracker]}
    ],
    Stop: [
      %{hooks: [MyApp.SessionSummary]}
    ]
  }
)
```

Each matcher config has:

- `:matcher` -- Regex pattern matched against tool names. Omit or set to `nil` to match all tools. Only applies to tool-based events (PreToolUse, PostToolUse, PostToolUseFailure).
- `:hooks` -- List of modules implementing `ClaudeCode.Hook` or 2-arity anonymous functions.
- `:timeout` -- Optional timeout in seconds for the hook execution.

### Events

| Event | When it fires | Return type |
|-------|--------------|-------------|
| `PreToolUse` | Before tool execution | `:allow`, `{:deny, reason}`, or `{:allow, updated_input}` |
| `PostToolUse` | After successful tool execution | `:ok` |
| `PostToolUseFailure` | After failed tool execution | `:ok` |
| `UserPromptSubmit` | When user submits a prompt | `:ok` or `{:reject, reason}` |
| `Stop` | When session is about to stop | `:ok` or `{:continue, reason}` |
| `SubagentStop` | When a subagent is about to stop | `:ok` or `{:continue, reason}` |
| `PreCompact` | Before context compaction | `:ok` or `{:instructions, text}` |
| `Notification` | On notification events | `:ok` |
| `SubagentStart` | When a subagent starts | `:ok` |

### Audit logging

```elixir
defmodule MyApp.AuditLogger do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PostToolUse"} = event, _tool_use_id) do
    MyApp.AuditLog.insert(%{
      tool: event.tool_name,
      input: event.tool_input,
      result: event.tool_response
    })
    :ok
  end
end
```

### Budget guard

Use a `Stop` hook to keep a session running when budget remains:

```elixir
defmodule MyApp.BudgetGuard do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "Stop"}, _tool_use_id) do
    if MyApp.Budget.remaining() > 0 do
      {:continue, "Budget remaining, keep working"}
    else
      :ok
    end
  end
end
```

### Anonymous function hooks

You can use anonymous functions instead of modules for simple hooks:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      %{matcher: "Bash", hooks: [
        fn %{tool_input: %{"command" => cmd}}, _id ->
          Logger.info("Bash: #{cmd}")
          :ok
        end
      ]}
    ]
  }
)
```

## Using Both Together

`:can_use_tool` handles permission decisions while hooks handle lifecycle observation and other event types:

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: MyApp.ToolPermissions,
  hooks: %{
    PostToolUse: [%{hooks: [MyApp.AuditLogger]}],
    Stop: [%{hooks: [MyApp.BudgetGuard]}]
  }
)
```

## The Hook Behaviour

Both `:can_use_tool` and `:hooks` use the same `ClaudeCode.Hook` behaviour:

```elixir
defmodule MyApp.MyHook do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(input, tool_use_id) do
    # input is a map with event-specific fields like :tool_name, :tool_input, :hook_event_name
    # tool_use_id is a string identifier (or nil for non-tool events)
    :ok
  end
end
```

The `input` map contains fields that vary by event. Common fields include `:tool_name`, `:tool_input`, `:hook_event_name`, and `:tool_response` (for post-execution events).

If a callback raises an exception, `ClaudeCode.Hook.invoke/3` catches it and returns `{:error, reason}`, which is translated to a safe default response on the wire.

## Next Steps

- [User Approvals and Input](user-input.md) -- Programmatic tool approval with `can_use_tool`
- [Permissions](permissions.md) -- Static permission modes and tool restrictions
- [Sessions](sessions.md) -- Session management and conversation history
