# Hooks and can_use_tool Design

> Generated 2026-02-10 via brainstorming session.

**Goal:** Implement a unified hook system and `can_use_tool` permission callback for the Elixir SDK, closing the two largest feature parity gaps with the Python SDK.

**Prerequisites:** Control protocol implementation (Tasks 1-12 from `2026-02-09-control-protocol-impl.md`).

---

## Architecture Overview

Two separate options, two separate wire paths, one shared `ClaudeCode.Hook` behaviour:

| Option | CLI flag | Control request subtype | Purpose |
|--------|----------|------------------------|---------|
| `:can_use_tool` | `--permission-prompt-tool stdio` | `can_use_tool` (CLI -> SDK) | Permission decisions before tool execution |
| `:hooks` | _(none, registered in initialize handshake)_ | `hook_callback` (CLI -> SDK) | Lifecycle event callbacks |

Both can be used independently or together.

---

## 1. ClaudeCode.Hook Behaviour

A single behaviour used by both `can_use_tool` and hook callbacks:

```elixir
defmodule ClaudeCode.Hook do
  @moduledoc """
  Behaviour for hook callbacks.

  Implement this behaviour in a module, or pass an anonymous function
  with the same signature as `call/2`.

  The return type depends on which event the hook is registered for.
  """

  @type input :: map()
  @type tool_use_id :: String.t() | nil

  @callback call(input(), tool_use_id()) :: term()
end
```

All callbacks (modules or anonymous functions) share this `call/2` signature. The SDK validates return values based on context.

---

## 2. Return Types Per Event

### can_use_tool / PreToolUse (permission decisions)

```elixir
@type pre_tool_use_result ::
  :allow
  | {:allow, updated_input :: map()}
  | {:allow, updated_input :: map(), permissions: [permission_update()]}
  | {:deny, reason :: String.t()}
  | {:deny, reason :: String.t(), interrupt: true}
```

### PostToolUse / PostToolUseFailure (observation only)

```elixir
@type post_tool_use_result :: :ok
```

### UserPromptSubmit

```elixir
@type user_prompt_submit_result ::
  :ok
  | {:reject, reason :: String.t()}
```

### Stop / SubagentStop

```elixir
@type stop_result ::
  :ok
  | {:continue, reason :: String.t()}
```

### PreCompact

```elixir
@type pre_compact_result ::
  :ok
  | {:instructions, String.t()}
```

### Notification / SubagentStart (observation only)

```elixir
@type notification_result :: :ok
```

### Permission Update Types (for PreToolUse)

```elixir
@type permission_update :: %{
  type: :add_rules | :replace_rules | :remove_rules |
        :set_mode | :add_directories | :remove_directories,
  optional(:rules) => [%{tool_name: String.t(), rule_content: String.t()}],
  optional(:behavior) => :allow | :deny,
  optional(:destination) => :session | :project | :user,
  optional(:mode) => String.t(),
  optional(:directories) => [String.t()]
}
```

---

## 3. Wire Format Mapping

| Elixir return | Wire format |
|---|---|
| `:allow` | `%{behavior: "allow"}` |
| `{:allow, input}` | `%{behavior: "allow", updatedInput: input}` |
| `{:allow, input, permissions: updates}` | `%{behavior: "allow", updatedInput: input, updatedPermissions: updates}` |
| `{:deny, reason}` | `%{behavior: "deny", message: reason}` |
| `{:deny, reason, interrupt: true}` | `%{behavior: "deny", message: reason, interrupt: true}` |
| `:ok` | `%{}` (empty response) |
| `{:continue, reason}` | `%{continue: false, stopReason: reason}` |
| `{:reject, reason}` | `%{decision: "block", reason: reason}` |
| `{:instructions, text}` | `%{hookSpecificOutput: %{customInstructions: text}}` |

---

## 4. Configuration

### can_use_tool (permission callback)

Accepts a module implementing `ClaudeCode.Hook` or an anonymous function:

```elixir
# Module
{:ok, session} = ClaudeCode.start_link(can_use_tool: MyApp.ToolPermissions)

# Anonymous function
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: fn %{tool_name: name}, _tool_use_id ->
    if name in ["Read", "Glob", "Grep"], do: :allow, else: {:deny, "Read-only mode"}
  end
)
```

Under the hood: sets `--permission-prompt-tool stdio` CLI flag. The CLI sends `can_use_tool` control requests.

### hooks (lifecycle callbacks)

A map of event names to lists of matcher configs, mirroring the Python SDK structure:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      %{matcher: "Bash", hooks: [MyApp.BashAuditor], timeout: 30},
      %{hooks: [MyApp.GlobalLogger]}  # nil matcher = match all tools
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

Each entry in the `hooks` list can be a module or anonymous function:

```elixir
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
```

The `matcher` field is a regex pattern matched against tool names. `nil` or omitted means match all tools. Matchers only apply to tool-based events (PreToolUse, PostToolUse, PostToolUseFailure).

### Both together

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: MyApp.ToolPermissions,
  hooks: %{
    PostToolUse: [%{hooks: [MyApp.AuditLogger]}],
    Stop: [%{hooks: [MyApp.BudgetGuard]}]
  }
)
```

### Validation rules

- `:can_use_tool` and `:permission_prompt_tool` cannot both be set (error)
- `:tool_callback` is deprecated — emit warning, still functional

---

## 5. Hook.Registry (Internal)

Pure-function module, no process. Handles callback ID assignment and lookup.

```elixir
defmodule ClaudeCode.Hook.Registry do
  @moduledoc false

  defstruct callbacks: %{}, counter: 0, can_use_tool: nil

  # Build registry from options, assign callback IDs
  def new(hooks_map, can_use_tool_callback) :: {registry, wire_format_hooks}

  # Look up callback module/function by ID (for hook_callback requests)
  def lookup(registry, callback_id) :: {:ok, callback} | :error

  # Get the can_use_tool callback (for can_use_tool requests)
  def get_can_use_tool(registry) :: callback | nil

  # Build the hooks wire format for initialize handshake
  def to_wire_format(registry) :: map() | nil
end
```

**Initialize handshake wire format:**

```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hookCallbackIds": ["hook_0"], "timeout": 30},
      {"matcher": null, "hookCallbackIds": ["hook_1"]}
    ],
    "PostToolUse": [
      {"matcher": "Write|Edit", "hookCallbackIds": ["hook_2"]}
    ]
  }
}
```

---

## 6. Adapter Routing

All hook/permission traffic is handled inside `Adapter.Local`, keeping it off the Session and message stream.

### On session start:

1. Build `Hook.Registry` from `:hooks` and `:can_use_tool` options
2. Store registry in adapter state
3. If `:can_use_tool` is set, `--permission-prompt-tool stdio` is in CLI flags
4. During initialize handshake, include hooks wire format from registry

### On inbound `can_use_tool` control request:

1. Adapter receives `%{"subtype" => "can_use_tool", "tool_name" => ..., "input" => ...}`
2. Calls `Registry.get_can_use_tool(registry)` to get callback
3. Calls `callback.call(input, tool_use_id)` (or `callback.(input, tool_use_id)` for fns)
4. Translates return value to wire format
5. Sends control response

### On inbound `hook_callback` control request:

1. Adapter receives `%{"subtype" => "hook_callback", "callback_id" => "hook_2", "input" => ...}`
2. Calls `Registry.lookup(registry, "hook_2")` to get callback
3. Calls the callback
4. Translates return value to wire format
5. Sends control response

### Execution model:

Hooks execute synchronously inside the adapter process. This is correct because the CLI is blocking on the control response. If a user's hook is slow, it blocks the adapter — which is the right backpressure since the CLI is waiting anyway.

---

## 7. Example Hook Implementations

### Permission gate

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
```

### Input rewriting

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

---

## 8. Files Changed

### New files (4)

| File | Purpose |
|------|---------|
| `lib/claude_code/hook.ex` | Behaviour definition, return types, default dispatch |
| `lib/claude_code/hook/registry.ex` | Callback ID assignment, lookup, wire format |
| `test/claude_code/hook_test.exs` | Behaviour and return type tests |
| `test/claude_code/hook/registry_test.exs` | Registry unit tests |

### Modified files (7)

| File | Change |
|------|--------|
| `lib/claude_code/options.ex` | Add `:can_use_tool` and `:hooks` validation. Deprecation warning on `:tool_callback` |
| `lib/claude_code/cli/command.ex` | Add `--permission-prompt-tool stdio` when `:can_use_tool` is set |
| `lib/claude_code/cli/control.ex` | Extend `initialize_request` for hooks wire format. Add `can_use_tool` response builder |
| `lib/claude_code/adapter/local.ex` | Store `Hook.Registry` in state. Route `can_use_tool` and `hook_callback` to callbacks |
| `docs/guides/hooks.md` | Full rewrite with hooks + can_use_tool |
| `docs/guides/user-input.md` | Full rewrite, replace SDK limitation with working examples |
| `test/claude_code/adapter/local_test.exs` | Tests for hook routing in adapter |

### Not in scope

- In-process MCP servers (`create_sdk_mcp_server` / `mcp_message`)
- `interrupt()`
- `extra_args`, `stderr` callback, `user` impersonation
- `tool_callback` removal (deprecated, not removed)

---

## 9. Migration from tool_callback

```elixir
# Before (deprecated)
ClaudeCode.start_link(
  tool_callback: fn event ->
    Logger.info("Tool #{event.name} completed")
  end
)

# After
ClaudeCode.start_link(
  hooks: %{
    PostToolUse: [%{hooks: [
      fn %{tool_name: name}, _id -> Logger.info("Tool #{name} completed"); :ok end
    ]}]
  }
)
```
