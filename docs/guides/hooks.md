# Hooks

Intercept and customize agent behavior at key execution points with hooks.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hooks). Examples are adapted for Elixir.

Hooks are callback functions that run your code in response to agent events, like a tool being called, a session starting, or execution stopping. With hooks, you can:

- **Block dangerous operations** before they execute, like destructive shell commands or unauthorized file access
- **Log and audit** every tool call for compliance, debugging, or analytics
- **Transform inputs and outputs** to sanitize data, inject credentials, or redirect file paths
- **Require human approval** for sensitive actions like database writes or API calls
- **Track session lifecycle** to manage state, clean up resources, or send notifications

This guide covers how hooks work, how to configure them, and provides examples for common patterns like blocking tools, modifying inputs, and forwarding notifications.

## How hooks work

1. **An event fires** -- Something happens during agent execution and the SDK fires an event: a tool is about to be called (`PreToolUse`), a tool returned a result (`PostToolUse`), a subagent started or stopped, the agent is idle, or execution finished. See the [full list of events](#available-hooks).
2. **The SDK collects registered hooks** -- The SDK checks for hooks registered for that event type, including callback hooks you pass in the `:hooks` option and shell command hooks from settings files (loaded via `:setting_sources`).
3. **Matchers filter which hooks run** -- If a hook has a [matcher](#matchers) pattern (like `"Write|Edit"`), the SDK tests it against the event's target (for example, the tool name). Hooks without a matcher run for every event of that type.
4. **Callback functions execute** -- Each matching hook's [callback function](#callback-function-inputs) receives input about what's happening: the tool name, its arguments, the session ID, and other event-specific details.
5. **Your callback returns a decision** -- After performing any operations (logging, API calls, validation), your callback returns an [output](#callback-outputs) that tells the agent what to do: allow the operation, block it, modify the input, or inject context into the conversation.

The following example puts these steps together. It registers a `PreToolUse` hook (step 1) with a `"Write|Edit"` matcher (step 3) so the callback only fires for file-writing tools. When triggered, the callback receives the tool's input (step 4), checks if the file path targets a `.env` file, and returns `{:deny, ...}` to block the operation (step 5):

```elixir
defmodule MyApp.ProtectEnvFiles do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_input: %{"file_path" => file_path}}, _tool_use_id) do
    if Path.basename(file_path) == ".env" do
      {:deny, permission_decision_reason: "Cannot modify .env files"}
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

This is a `PreToolUse` hook. It runs before the tool executes and can block or allow operations based on your logic.

> **MCP tools:** PreToolUse hooks also apply to in-process MCP tool calls. MCP tool names follow the `mcp__<server>__<tool>` pattern (e.g., `mcp__my-tools__get_weather`), so matchers like `"mcp__my-tools__.*"` work as expected.

## Available hooks

The SDK provides hooks for different stages of agent execution. Some hooks are available across all SDKs, while others are TypeScript-only.

| Hook Event | Elixir SDK | Python SDK | TypeScript SDK | What triggers it | Example use case |
|------------|------------|------------|----------------|------------------|------------------|
| `PreToolUse` | Yes | Yes | Yes | Tool call request (can block or modify) | Block dangerous shell commands |
| `PostToolUse` | Yes | Yes | Yes | Tool execution result | Log all file changes to audit trail |
| `PostToolUseFailure` | Yes | Yes | Yes | Tool execution failure | Handle or log tool errors |
| `UserPromptSubmit` | Yes | Yes | Yes | User prompt submission | Inject additional context into prompts |
| `Stop` | Yes | Yes | Yes | Agent execution stop | Save session state before exit |
| `SubagentStart` | Yes | Yes | Yes | Subagent initialization | Track parallel task spawning |
| `SubagentStop` | Yes | Yes | Yes | Subagent completion | Aggregate results from parallel tasks |
| `PreCompact` | Yes | Yes | Yes | Conversation compaction request | Archive full transcript before summarizing |
| `Notification` | Yes | Yes | Yes | Agent status messages | Send agent status updates externally |
| `PermissionRequest` | Yes | Yes | Yes | Permission dialog would be displayed | Custom permission handling |
| `SessionStart` | No | No | Yes | Session initialization | Initialize logging and telemetry |
| `SessionEnd` | No | No | Yes | Session termination | Clean up temporary resources |
| `Setup` | No | No | Yes | Session setup/maintenance | Run initialization tasks |
| `TeammateIdle` | No | No | Yes | Teammate becomes idle | Reassign work or notify |
| `TaskCompleted` | No | No | Yes | Background task completes | Aggregate results from parallel tasks |
| `ConfigChange` | No | No | Yes | Configuration file changes | Reload settings dynamically |
| `WorktreeCreate` | No | No | Yes | Git worktree created | Track isolated workspaces |
| `WorktreeRemove` | No | No | Yes | Git worktree removed | Clean up workspace resources |

> **Note:** The TypeScript-only hook events (`SessionStart`, `SessionEnd`, `Setup`, `ConfigChange`, `TeammateIdle`, `TaskCompleted`, `WorktreeCreate`, `WorktreeRemove`) are not emitted by the CLI to SDK consumers. They are handled internally by the TypeScript SDK and are not available in the Elixir or Python SDKs.

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

### Shorthand syntax

When you don't need a matcher, timeout, or `:where`, pass a bare module or 2-arity function directly:

```elixir
# Shorthand — bare module or function
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [MyApp.BashGuard],
    PostToolUse: [fn _input, _id -> :ok end]
  }
)

# Mixed — shorthand alongside full matcher configs
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      MyApp.GlobalGuard,                                       # shorthand
      %{matcher: "Bash", hooks: [MyApp.BashGuard], timeout: 30}  # full form
    ]
  }
)
```

The shorthand is equivalent to `%{hooks: [MyModule]}` — registered without a matcher (matches all tools) and with default timeout.

Your hook callbacks receive input data about the event and return a response so the agent knows to allow, block, or modify the operation. See `ClaudeCode.Hook` for the full event reference with input fields and return values per event.

### Matchers

Use matchers to filter which tools trigger your callbacks:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:matcher` | `string` | `nil` | Regex pattern to match tool names. Built-in tools include `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`, `WebFetch`, `Agent`, and others. MCP tools use the pattern `mcp__<server>__<action>`. |
| `:hooks` | `list` | -- | Required. List of callback modules or 2-arity anonymous functions to execute when the pattern matches |
| `:timeout` | `integer` | `60` | Timeout in seconds; increase for hooks that make external API calls |

Use the `:matcher` pattern to target specific tools whenever possible. A matcher with `"Bash"` only runs for Bash commands, while omitting the pattern runs your callbacks for every tool call. Note that matchers only filter by **tool name**, not by file paths or other arguments -- to filter by file path, check `tool_input` inside your callback.

Matchers only apply to tool-based hooks (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`). For lifecycle hooks like `Stop`, `SubagentStop`, and `Notification`, matchers are ignored and the hook fires for all events of that type.

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

1. **Input data** (`map`): Event details — see `ClaudeCode.Hook` for the full field reference per event
2. **Tool use ID** (`String.t() | nil`): Correlate `PreToolUse` and `PostToolUse` events

Both modules implementing `ClaudeCode.Hook` and anonymous functions receive the same arguments via `call/2`.

> **Key normalization:** Hook input fields are converted to atom keys. All documented fields are guaranteed to be atoms. Unknown or future fields fall back to `String.to_existing_atom/1` — if the atom doesn't already exist at runtime, the key is preserved as a string, avoiding unbounded atom creation.

### Callback outputs

Your callback function returns a value that tells the SDK how to proceed. The return type depends on the hook event — see `ClaudeCode.Hook` for return values per event.

> The hook response module handles translating these idiomatic Elixir returns to the CLI wire format (including `hookSpecificOutput`, `permissionDecision`, and other fields). You do not need to construct wire-format maps directly. The wire format also supports top-level fields like `continue`, `stopReason`, `suppressOutput`, and `systemMessage` for injecting context into the conversation -- see the [official docs](https://platform.claude.com/docs/en/agent-sdk/hooks) for the full wire protocol.

#### Permission decision flow

When multiple hooks or permission rules apply, the SDK evaluates them in this order:

1. **Deny** rules are checked first (any match = immediate denial).
2. **Ask** rules are checked second.
3. **Allow** rules are checked third.
4. **Default to Ask** if nothing matches.

If any hook returns `{:deny, permission_decision_reason: reason}`, the operation is blocked -- other hooks returning `:allow` will not override it.

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
      String.contains?(cmd, "rm -rf") -> {:deny, message: "Destructive command blocked"}
      String.starts_with?(cmd, "sudo") -> {:deny, message: "No sudo allowed"}
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
    if name in ["Read", "Glob", "Grep"], do: :allow, else: {:deny, message: "Read-only mode"}
  end
)
```

### Return values

| Return | Effect |
|--------|--------|
| `:allow` | Permit the tool call |
| `{:allow, updated_input: %{...}}` | Permit with modified input |
| `{:allow, updated_permissions: [...]}` | Permit with updated permission rules |
| `:deny` | Block the tool call |
| `{:deny, message: "reason"}` | Block with an explanation |
| `{:deny, message: "reason", interrupt: true}` | Block and interrupt the session |

### How it works

When `:can_use_tool` is set, the SDK automatically adds `--permission-prompt-tool stdio` to the CLI flags. The CLI sends a control request before each tool execution, and the adapter invokes your callback synchronously to get a decision.

> **Note:** `:can_use_tool` and `:permission_prompt_tool` cannot be used together. If you need programmatic tool approval, use `:can_use_tool`.

### Using can_use_tool with hooks

`:can_use_tool` handles permission decisions while hooks handle lifecycle observation and other event types:

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: MyApp.ToolPermissions,
  hooks: %{
    PostToolUse: [MyApp.AuditLogger],
    Stop: [MyApp.BudgetGuard]
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

The `input` map contains fields that vary by event. See `ClaudeCode.Hook` for the complete input fields and return values per event type.

If a callback raises an exception, `ClaudeCode.Hook.invoke/3` catches it and returns `{:error, reason}`, which is translated to a safe default response on the wire.

## Handle advanced scenarios

These patterns help you build more sophisticated hook systems for complex use cases.

### Chaining multiple hooks

Hooks execute in the order they appear in the list. Keep each hook focused on a single responsibility and chain multiple hooks for complex logic:

```elixir
{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    PreToolUse: [
      MyApp.RateLimiter,         # First: check rate limits
      MyApp.AuthorizationCheck,  # Second: verify permissions
      MyApp.InputSanitizer,      # Third: sanitize inputs
      MyApp.AuditLogger          # Last: log the action
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

### Modify tool input

Return updated input to change what the tool receives:

```elixir
defmodule MyApp.RedirectToSandbox do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_name: "Write", tool_input: input}, _tool_use_id) do
    original_path = Map.get(input, "file_path", "")
    {:allow, updated_input: Map.put(input, "file_path", "/sandbox#{original_path}")}
  end

  def call(_input, _tool_use_id), do: :ok
end
```

> When using `{:allow, updated_input: new_map}`, always return a new map rather than mutating the original `tool_input`. The hook response module automatically includes the required `permissionDecision: "allow"` in the wire format when you return `{:allow, updated_input: ...}`.

### Auto-approve specific tools

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

### Block and inject context

This example blocks any attempt to write to the `/etc` directory and uses two output mechanisms together: `{:deny, ...}` stops the tool call, while the full `%ClaudeCode.Hook.Output{}` struct injects a `system_message` into the conversation so the agent receives context about why the operation was blocked and avoids retrying it:

```elixir
defmodule MyApp.BlockEtcWrites do
  @behaviour ClaudeCode.Hook

  alias ClaudeCode.Hook.Output
  alias ClaudeCode.Hook.Output.PreToolUse, as: PreToolUseOutput

  @impl true
  def call(%{hook_event_name: "PreToolUse", tool_input: %{"file_path" => path}}, _tool_use_id) do
    if String.starts_with?(path, "/etc") do
      %Output{
        system_message: "Remember: system directories like /etc are protected.",
        hook_specific_output: %PreToolUseOutput{
          permission_decision: "deny",
          permission_decision_reason: "Writing to /etc is not allowed"
        }
      }
    else
      :ok
    end
  end

  def call(_input, _tool_use_id), do: :ok
end
```

### Track subagent activity

Use `SubagentStop` hooks to monitor when subagents finish their work. This example logs a summary each time a subagent completes:

```elixir
defmodule MyApp.SubagentTracker do
  @behaviour ClaudeCode.Hook
  require Logger

  @impl true
  def call(%{hook_event_name: "SubagentStop"} = input, tool_use_id) do
    Logger.info("[SUBAGENT] Completed: #{input[:agent_id]}")
    Logger.info("  Transcript: #{input[:agent_transcript_path]}")
    Logger.info("  Tool use ID: #{tool_use_id}")
    Logger.info("  Stop hook active: #{input[:stop_hook_active]}")
    :ok
  end

  def call(_input, _tool_use_id), do: :ok
end

{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    SubagentStop: [MyApp.SubagentTracker]
  }
)
```

### Forward notifications

Use `Notification` hooks to receive status notifications from the agent and forward them to external services. Notifications fire for specific event types: `permission_prompt` (Claude needs permission), `idle_prompt` (Claude is waiting for input), `auth_success` (authentication completed), and `elicitation_dialog` (Claude is prompting the user). Each notification includes a `:message` field with a human-readable description and optionally a `:title`.

This example forwards every notification to Slack via an incoming webhook:

```elixir
defmodule MyApp.SlackNotifier do
  @behaviour ClaudeCode.Hook
  require Logger

  @impl true
  def call(%{hook_event_name: "Notification", message: message}, _tool_use_id) do
    Task.start(fn ->
      case Req.post("https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
             json: %{text: "Agent status: #{message}"}) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Slack notification failed: #{inspect(reason)}")
      end
    end)

    :ok
  end

  def call(_input, _tool_use_id), do: :ok
end

{:ok, session} = ClaudeCode.start_link(
  hooks: %{
    Notification: [MyApp.SlackNotifier]
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
          :ok
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
- For `SubagentStop`, `Stop`, and `Notification` hooks, matchers are ignored. These hooks fire for all events of that type.
- Hooks may not fire when the agent hits the `:max_turns` limit because the session ends before hooks can execute

### Matcher not filtering as expected

Matchers only match **tool names**, not file paths or other arguments. To filter by file path, check `tool_input` inside your hook:

```elixir
def call(%{hook_event_name: "PreToolUse", tool_input: %{"file_path" => path}}, _id) do
  if String.ends_with?(path, ".md") do
    # Process markdown files...
    :ok
  else
    :ok
  end
end
```

### Hook timeout

- Increase the `:timeout` value in the matcher configuration
- For long-running async work, consider using `Task.start/1` to fire-and-forget

### Tool blocked unexpectedly

- Check all `PreToolUse` hooks for `{:deny, permission_decision_reason: reason}` returns
- Add logging to your hooks to see what reasons they are returning
- Verify matcher patterns are not too broad (an omitted matcher matches all tools)

### Modified input not applied

- When using `{:allow, updated_input: new_map}`, ensure you are returning a complete input map, not just the changed fields
- The hook response module translates `{:allow, updated_input: ...}` to the correct wire format including `hookSpecificOutput` and `permissionDecision`
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

### systemMessage not appearing in output

The `system_message` field (via the full `%ClaudeCode.Hook.Output{}` struct) adds context to the conversation that the model sees, but it may not appear in all SDK output modes. If you need to surface hook decisions to your application, log them separately or use a dedicated output channel.

## Related resources

- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) -- Full JSON input/output schemas, event documentation, and matcher patterns
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide) -- Shell command hook examples and walkthroughs

## Next steps

- [Permissions](permissions.md) -- Control what your agent can do
- [Custom Tools](custom-tools.md) -- Build tools to extend agent capabilities
- [User Input](user-input.md) -- Tool approval, clarifying questions, and user input flows
- [Sessions](sessions.md) -- Session management and conversation history
