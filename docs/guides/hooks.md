# Hooks

Intercept and customize agent behavior at key execution points with hooks.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hooks). Examples are adapted for Elixir.

Hooks let you intercept agent execution at key points to add validation, logging, security controls, or custom logic. With hooks, you can:

- **Block dangerous operations** before they execute, like destructive shell commands or unauthorized file access
- **Log and audit** every tool call for compliance, debugging, or analytics
- **Transform inputs and outputs** to sanitize data, inject credentials, or redirect file paths
- **Require human approval** for sensitive actions like database writes or API calls
- **Track session lifecycle** to manage state, clean up resources, or send notifications

A hook has two parts:

1. **The callback function**: the logic that runs when the hook fires
2. **The hook configuration**: tells the SDK which event to hook into (like `PreToolUse`) and which tools to match

The following example blocks the agent from modifying `.env` files. First, define a callback that checks the file path, then pass it via the `:hooks` option:

```elixir
defmodule MyApp.ProtectEnvFiles do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_input: %{"file_path" => file_path}}, _tool_use_id) do
    if Path.basename(file_path) == ".env" do
      {:deny, "Cannot modify .env files"}
    else
      :allow
    end
  end

  def call(_input, _tool_use_id), do: :ok
end

# Register the hook for PreToolUse events
# The matcher filters to only Write and Edit tool calls
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      %{matcher: "Write|Edit", hooks: [MyApp.ProtectEnvFiles]}
    ]
  }
)
```

This is a `PreToolUse` hook. It runs before the tool executes and can block or allow operations based on your logic. The rest of this guide covers all available hooks, their configuration options, and patterns for common use cases.

## Available hooks

The SDK provides hooks for different stages of agent execution:

| Hook Event | Supported | What triggers it | Example use case |
|------------|-----------|------------------|------------------|
| `PreToolUse` | Yes | Tool call request (can block or modify) | Block dangerous shell commands |
| `PostToolUse` | Yes | Tool execution result | Log all file changes to audit trail |
| `PostToolUseFailure` | Yes | Tool execution failure | Handle or log tool errors |
| `UserPromptSubmit` | Yes | User prompt submission | Inject additional context into prompts |
| `Stop` | Yes | Agent execution stop | Save session state before exit |
| `SubagentStart` | Yes | Subagent initialization | Track parallel task spawning |
| `SubagentStop` | Yes | Subagent completion | Aggregate results from parallel tasks |
| `PreCompact` | Yes | Conversation compaction request | Archive full transcript before summarizing |
| `Notification` | Yes | Agent status messages | Send agent status updates externally |

> **Note:** The official TypeScript SDK also supports `PermissionRequest`, `SessionStart`, and `SessionEnd` hooks. These are not yet implemented in the Elixir SDK. The Python SDK supports a subset of these hooks -- see the [official docs](https://platform.claude.com/docs/en/agent-sdk/hooks) for the full compatibility matrix.

## Common use cases

Hooks are flexible enough to handle many different scenarios. Here are some of the most common patterns:

- **Security** -- Block dangerous commands (like `rm -rf /`, destructive SQL), validate file paths before write operations, enforce allowlists/blocklists for tool usage
- **Logging** -- Create audit trails of all agent actions, track execution metrics and performance, debug agent behavior in development
- **Tool interception** -- Redirect file operations to sandboxed directories, inject environment variables or credentials, transform tool inputs or outputs
- **Authorization** -- Implement role-based access control, require human approval for sensitive operations, rate limit specific tool usage

## Configure hooks

Pass hooks in the `:hooks` option when starting a session:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [%{matcher: "Bash", hooks: [MyApp.BashAuditor]}]
  }
)
```

The `:hooks` option is a map where:
- **Keys** are [hook event names](#available-hooks) (e.g., `PreToolUse`, `PostToolUse`, `Stop`)
- **Values** are lists of [matchers](#matchers), each containing an optional filter pattern and your [callback functions](#callback-function-inputs)

Your hook callbacks receive [input data](#input-data) about the event and return a [response](#callback-outputs) so the agent knows to allow, block, or modify the operation.

### Matchers

Use matchers to filter which tools trigger your callbacks:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:matcher` | `string` | `nil` | Regex pattern to match tool names. Built-in tools include `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`, `WebFetch`, `Task`, and others. MCP tools use the pattern `mcp__<server>__<action>`. |
| `:hooks` | `list` | -- | Required. List of callback modules or 2-arity anonymous functions to execute when the pattern matches |
| `:timeout` | `integer` | `60` | Timeout in seconds; increase for hooks that make external API calls |

Use the `:matcher` pattern to target specific tools whenever possible. A matcher with `"Bash"` only runs for Bash commands, while omitting the pattern runs your callbacks for every tool call. Note that matchers only filter by **tool name**, not by file paths or other arguments -- to filter by file path, check `tool_input` inside your callback.

Matchers only apply to tool-based hooks (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`). For lifecycle hooks like `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, and `Notification`, matchers are ignored and the hook fires for all events of that type.

> **Discovering tool names:** Check the `tools` array in the initial system message when your session starts, or add a hook without a matcher to log all tool calls.
>
> **MCP tool naming:** MCP tools always start with `mcp__` followed by the server name and action: `mcp__<server>__<action>`. For example, if you configure a server named `playwright`, its tools will be named `mcp__playwright__browser_screenshot`, `mcp__playwright__browser_click`, etc. The server name comes from the key you use in the MCP servers configuration.

This example uses a matcher to run a hook only for file-modifying tools:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      %{matcher: "Write|Edit", hooks: [MyApp.ValidateFilePath]}
    ]
  }
)
```

### Callback function inputs

Every hook callback receives two arguments:

1. **Input data** (`map`): Event details. See [input data](#input-data) for fields
2. **Tool use ID** (`String.t() | nil`): Correlate `PreToolUse` and `PostToolUse` events

Both modules implementing `ClaudeCode.Hook` and anonymous functions receive the same arguments via `call/2`.

### Input data

The first argument to your hook callback contains information about the event.

**Common fields** present in all hook types:

| Field | Type | Description |
|-------|------|-------------|
| `:hook_event_name` | `String.t()` | The hook type (`"PreToolUse"`, `"PostToolUse"`, etc.) |
| `:session_id` | `String.t()` | Current session identifier |
| `:transcript_path` | `String.t()` | Path to the conversation transcript |
| `:cwd` | `String.t()` | Current working directory |

**Hook-specific fields** vary by hook type:

| Field | Type | Description | Hooks |
|-------|------|-------------|-------|
| `:tool_name` | `String.t()` | Name of the tool being called | PreToolUse, PostToolUse, PostToolUseFailure |
| `:tool_input` | `map` | Arguments passed to the tool | PreToolUse, PostToolUse, PostToolUseFailure |
| `:tool_response` | `any` | Result returned from tool execution | PostToolUse |
| `:error` | `String.t()` | Error message from tool execution failure | PostToolUseFailure |
| `:is_interrupt` | `boolean` | Whether the failure was caused by an interrupt | PostToolUseFailure |
| `:prompt` | `String.t()` | The user's prompt text | UserPromptSubmit |
| `:stop_hook_active` | `boolean` | Whether a stop hook is currently processing | Stop, SubagentStop |
| `:agent_id` | `String.t()` | Unique identifier for the subagent | SubagentStart, SubagentStop |
| `:agent_type` | `String.t()` | Type/role of the subagent | SubagentStart |
| `:agent_transcript_path` | `String.t()` | Path to the subagent's conversation transcript | SubagentStop |
| `:trigger` | `String.t()` | What triggered compaction: `"manual"` or `"auto"` | PreCompact |
| `:custom_instructions` | `String.t()` | Custom instructions provided for compaction | PreCompact |
| `:message` | `String.t()` | Status message from the agent | Notification |
| `:notification_type` | `String.t()` | Type of notification: `"permission_prompt"`, `"idle_prompt"`, `"auth_success"`, or `"elicitation_dialog"` | Notification |
| `:title` | `String.t()` | Optional title set by the agent | Notification |

The code below defines a hook callback that uses `:tool_name` and `:tool_input` to log details about each tool call:

```elixir
defmodule MyApp.ToolLogger do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_name: name, tool_input: input}, _tool_use_id) do
    Logger.info("Tool: #{name}, Input: #{inspect(input)}")
    :allow
  end

  def call(_input, _tool_use_id), do: :ok
end
```

### Callback outputs

Your callback function returns a value that tells the SDK how to proceed. The return type depends on the hook event.

#### PreToolUse return values

| Return | Effect |
|--------|--------|
| `:allow` | Permit the tool call |
| `{:allow, updated_input}` | Permit with modified input |
| `{:deny, reason}` | Block the tool call with an explanation |

> **Note:** The CLI wire format also supports an `"ask"` permission decision, which prompts the user for confirmation. The Elixir SDK currently maps `:allow` and `{:deny, reason}` to the corresponding wire decisions. If you need `"ask"` behavior, you can implement it by omitting any hook for the tool and letting the default permission flow handle it.

#### PostToolUse / PostToolUseFailure / Notification / SubagentStart

| Return | Effect |
|--------|--------|
| `:ok` | Acknowledge the event (observation only) |

#### UserPromptSubmit

| Return | Effect |
|--------|--------|
| `:ok` | Allow the prompt |
| `{:reject, reason}` | Block the prompt submission |

#### Stop / SubagentStop

| Return | Effect |
|--------|--------|
| `:ok` | Allow the session to stop |
| `{:continue, reason}` | Keep the session running |

#### PreCompact

| Return | Effect |
|--------|--------|
| `:ok` | Allow compaction normally |
| `{:instructions, text}` | Provide custom instructions for compaction |

> The hook response module handles translating these idiomatic Elixir returns to the CLI wire format (including `hookSpecificOutput`, `permissionDecision`, and other fields). You do not need to construct wire-format maps directly. The wire format also supports top-level fields like `continue`, `stopReason`, `suppressOutput`, and `systemMessage` for injecting context into the conversation -- see the [official docs](https://platform.claude.com/docs/en/agent-sdk/hooks) for the full wire protocol.

#### Permission decision flow

When multiple hooks or permission rules apply, the SDK evaluates them in this order:

1. **Deny** rules are checked first (any match = immediate denial).
2. **Ask** rules are checked second.
3. **Allow** rules are checked third.
4. **Default to Ask** if nothing matches.

If any hook returns `{:deny, reason}`, the operation is blocked -- other hooks returning `:allow` will not override it.

#### Block a tool

Return a deny decision to prevent tool execution:

```elixir
defmodule MyApp.BlockDangerous do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_input: %{"command" => cmd}}, _tool_use_id) do
    if String.contains?(cmd, "rm -rf /") do
      {:deny, "Dangerous command blocked: rm -rf /"}
    else
      :allow
    end
  end

  def call(_input, _tool_use_id), do: :ok
end
```

#### Modify tool input

Return updated input to change what the tool receives:

```elixir
defmodule MyApp.RedirectToSandbox do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_name: "Write", tool_input: input}, _tool_use_id) do
    original_path = Map.get(input, "file_path", "")
    {:allow, Map.put(input, "file_path", "/sandbox#{original_path}")}
  end

  def call(_input, _tool_use_id), do: :ok
end
```

> When using `{:allow, updated_input}`, always return a new map rather than mutating the original `tool_input`. The hook response module automatically includes the required `permissionDecision: "allow"` in the wire format when you return `{:allow, updated_input}`.

#### Auto-approve specific tools

Bypass permission prompts for trusted tools. This is useful when you want certain operations to run without user confirmation:

```elixir
defmodule MyApp.AutoApproveReadOnly do
  @behaviour ClaudeCode.Hook

  @read_only_tools ~w(Read Glob Grep LS)

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_name: name}, _tool_use_id)
      when name in @read_only_tools do
    :allow
  end

  def call(_input, _tool_use_id), do: :ok
end
```

## can_use_tool

> **Elixir-specific:** The `:can_use_tool` option is an Elixir SDK convenience that provides a simpler API for permission decisions. It registers a single permission callback that the CLI invokes before every tool execution, without needing matcher configuration.

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

### How it works

When `:can_use_tool` is set, the SDK automatically adds `--permission-prompt-tool stdio` to the CLI flags. The CLI sends a control request before each tool execution, and the adapter invokes your callback synchronously to get a decision.

> **Note:** `:can_use_tool` and `:permission_prompt_tool` cannot be used together. If you need programmatic tool approval, use `:can_use_tool`.

### Using can_use_tool with hooks

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

## The Hook behaviour

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

## Handle advanced scenarios

These patterns help you build more sophisticated hook systems for complex use cases.

### Chaining multiple hooks

Hooks execute in the order they appear in the list. Keep each hook focused on a single responsibility and chain multiple hooks for complex logic:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      %{hooks: [MyApp.RateLimiter]},         # First: check rate limits
      %{hooks: [MyApp.AuthorizationCheck]},   # Second: verify permissions
      %{hooks: [MyApp.InputSanitizer]},       # Third: sanitize inputs
      %{hooks: [MyApp.AuditLogger]}           # Last: log the action
    ]
  }
)
```

### Tool-specific matchers with regex

Use regex patterns to match multiple tools:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      # Match file modification tools
      %{matcher: "Write|Edit|Delete", hooks: [MyApp.FileSecurityHook]},
      # Match all MCP tools
      %{matcher: "^mcp__", hooks: [MyApp.McpAuditHook]},
      # Match everything (no matcher)
      %{hooks: [MyApp.GlobalLogger]}
    ]
  }
)
```

> Matchers only match **tool names**, not file paths or other arguments. To filter by file path, check `tool_input` inside your hook callback.

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

  def call(_input, _tool_use_id), do: :ok
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

  def call(_input, _tool_use_id), do: :ok
end
```

### Tracking subagent activity

Use `SubagentStop` hooks to monitor subagent completion. The `tool_use_id` helps correlate parent agent calls with their subagents:

```elixir
defmodule MyApp.SubagentTracker do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "SubagentStop", stop_hook_active: active}, tool_use_id) do
    Logger.info("[SUBAGENT] Completed, tool_use_id: #{tool_use_id}, stop_hook_active: #{active}")
    :ok
  end

  def call(_input, _tool_use_id), do: :ok
end

{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    SubagentStop: [%{hooks: [MyApp.SubagentTracker]}]
  }
)
```

### Async operations in hooks

Hooks can perform async operations like HTTP requests. Handle errors gracefully by catching exceptions instead of raising them:

```elixir
defmodule MyApp.WebhookNotifier do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PostToolUse", tool_name: name}, _tool_use_id) do
    Task.start(fn ->
      case Req.post("https://api.example.com/webhook",
             json: %{tool: name, timestamp: DateTime.utc_now()}) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Webhook failed: #{inspect(reason)}")
      end
    end)

    :ok
  end

  def call(_input, _tool_use_id), do: :ok
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
          :allow
        end
      ]}
    ]
  }
)
```

## Fix common issues

This section covers common issues and how to resolve them.

### Hook not firing

- Verify the hook event name is correct and case-sensitive (`PreToolUse`, not `preToolUse` or `:pre_tool_use`)
- Check that your matcher pattern matches the tool name exactly
- Ensure the hook is under the correct event type in the `:hooks` map
- For `SubagentStop`, `Stop`, `SessionStart`, `SessionEnd`, and `Notification` hooks, matchers are ignored. These hooks fire for all events of that type.
- Hooks may not fire when the agent hits the `:max_turns` limit because the session ends before hooks can execute

### Matcher not filtering as expected

Matchers only match **tool names**, not file paths or other arguments. To filter by file path, check `tool_input` inside your hook:

```elixir
def call(%{hook_event_name: "PreToolUse", tool_input: %{"file_path" => path}}, _id) do
  if String.ends_with?(path, ".md") do
    # Process markdown files...
    :allow
  else
    :allow
  end
end
```

### Hook timeout

- Increase the `:timeout` value in the matcher configuration
- For long-running async work, consider using `Task.start/1` to fire-and-forget

### Tool blocked unexpectedly

- Check all `PreToolUse` hooks for `{:deny, reason}` returns
- Add logging to your hooks to see what reasons they are returning
- Verify matcher patterns are not too broad (an omitted matcher matches all tools)

### Modified input not applied

- When using `{:allow, updated_input}`, ensure you are returning a complete input map, not just the changed fields
- The hook response module translates `{:allow, updated_input}` to the correct wire format including `hookSpecificOutput` and `permissionDecision`
- On the wire, `updatedInput` must be inside `hookSpecificOutput` alongside `permissionDecision: "allow"` -- the Elixir SDK handles this automatically

### can_use_tool and permission_prompt_tool conflict

`:can_use_tool` and `:permission_prompt_tool` cannot be used together. If both are set, the SDK will raise an error. Use `:can_use_tool` for programmatic tool approval.

### Subagent permission prompts multiplying

When spawning multiple subagents, each one may request permissions separately. Subagents do not automatically inherit parent agent permissions. To avoid repeated prompts, use `PreToolUse` hooks to auto-approve specific tools, or configure permission rules that apply to subagent sessions.

### Recursive hook loops with subagents

A `UserPromptSubmit` hook that spawns subagents can create infinite loops if those subagents trigger the same hook. To prevent this:

- Check for a subagent indicator in the hook input before spawning
- Use the `parent_tool_use_id` field to detect if you are already in a subagent context
- Scope hooks to only run for the top-level agent session

## Next steps

- [Permissions](permissions.md) -- Control what your agent can do
- [Custom Tools](custom-tools.md) -- Build tools to extend agent capabilities
- [User Input](user-input.md) -- Tool approval, clarifying questions, and user input flows
- [Sessions](sessions.md) -- Session management and conversation history
