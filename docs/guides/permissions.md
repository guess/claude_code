# Permissions

Control how your agent uses tools with permission modes, hooks, and declarative allow/deny rules.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/permissions). Examples are adapted for Elixir.

---

The Elixir SDK provides permission controls to manage how Claude uses tools. Use permission modes and tool rules to define what is allowed automatically, and the [`:can_use_tool` callback](hooks.md#can_use_tool) to handle everything else at runtime.

> This page covers permission modes and rules. To build interactive approval flows where users approve or deny tool requests at runtime, see [Handle approvals and user input](user-input.md).

## How permissions are evaluated

When Claude requests a tool, the SDK checks permissions in this order:

1. **Hooks** -- Run [hooks](hooks.md) first, which can allow, deny, or continue to the next step.
2. **Deny rules** -- Check `deny` rules (from `:disallowed_tools` and [settings.json](https://code.claude.com/docs/en/settings#permission-settings)). If a deny rule matches, the tool is blocked, even in `:bypass_permissions` mode.
3. **Permission mode** -- Apply the active [permission mode](#permission-modes). `:bypass_permissions` approves everything that reaches this step. `:accept_edits` approves file operations. Other modes fall through.
4. **Allow rules** -- Check `allow` rules (from `:allowed_tools` and settings.json). If a rule matches, the tool is approved.
5. **`can_use_tool` callback** -- If not resolved by any of the above, call your [`:can_use_tool` callback](hooks.md#can_use_tool) for a decision. This can be a module implementing `ClaudeCode.Hook` or a 2-arity function. In `:dont_ask` mode, this step is skipped and the tool is denied.

This page focuses on **allow and deny rules** and **permission modes**. For the other steps:

- **Hooks**: run custom code to allow, deny, or modify tool requests. See [Control execution with hooks](hooks.md).
- **`can_use_tool` callback**: prompt users for approval at runtime or implement programmatic decisions. See [Hooks: can_use_tool](hooks.md#can_use_tool) and [Handle approvals and user input](user-input.md).

## Allow and deny rules

`:allowed_tools` and `:disallowed_tools` add entries to the allow and deny rule lists in the evaluation flow above. They control whether a tool call is approved, not whether the tool is available to Claude.

| Option | Effect |
| :----- | :----- |
| `allowed_tools: ["Read", "Grep"]` | `Read` and `Grep` are auto-approved. Tools not listed here still exist and fall through to the permission mode and `can_use_tool`. |
| `disallowed_tools: ["Bash"]` | `Bash` is always denied. Deny rules are checked first and hold in every permission mode, including `:bypass_permissions`. |

For a locked-down agent, pair `:allowed_tools` with `permission_mode: :dont_ask`. Listed tools are approved; anything else is denied outright instead of prompting:

```elixir
{:ok, result} = ClaudeCode.query(
  "Analyze this codebase",
  allowed_tools: ["Read", "Glob", "Grep"],
  permission_mode: :dont_ask
)
```

> **Warning:** `:allowed_tools` does not constrain `:bypass_permissions`. `:allowed_tools` only pre-approves the tools you list. Unlisted tools are not matched by any allow rule and fall through to the permission mode, where `:bypass_permissions` approves them. Setting `allowed_tools: ["Read"]` alongside `permission_mode: :bypass_permissions` still approves every tool, including `Bash`, `Write`, and `Edit`. If you need `:bypass_permissions` but want specific tools blocked, use `:disallowed_tools`.

You can also configure allow, deny, and ask rules declaratively in `.claude/settings.json`. The SDK does not load filesystem settings by default, so you must set `setting_sources: ["project"]` in your options for these rules to apply. See [Permission settings](https://code.claude.com/docs/en/settings#permission-settings) for the rule syntax.

## Permission modes

Permission modes provide global control over how Claude uses tools. You can set the permission mode when calling `ClaudeCode.query/2`, when starting a session, or change it dynamically during streaming sessions.

### Available modes

The SDK supports these permission modes:

| Mode                  | Description                  | Tool behavior                                                                         |
| :-------------------- | :--------------------------- | :------------------------------------------------------------------------------------ |
| `:default`            | Standard permission behavior | No auto-approvals; unmatched tools trigger your `can_use_tool` callback or are rejected |
| `:accept_edits`       | Auto-accept file edits       | File edits and [filesystem operations](#accept-edits-mode-accept_edits) (`mkdir`, `rm`, `mv`, etc.) are automatically approved |
| `:bypass_permissions` | Bypass all permission checks | All tools run without permission prompts (use with caution)                            |
| `:plan`               | Planning mode                | No tool execution; Claude plans without making changes                                 |
| `:delegate`           | Delegate to permission tool  | All permission decisions are delegated to your `can_use_tool` callback                 |
| `:dont_ask`           | Deny unmatched tools         | Tools not explicitly allowed by rules are denied without prompting                     |

> **Warning:** When using `:bypass_permissions`, all subagents inherit this mode and it cannot be overridden. Subagents may have different system prompts and less constrained behavior than your main agent. Enabling `:bypass_permissions` grants them full, autonomous system access without any approval prompts.

### Set permission mode

You can set the permission mode once when starting a query or session, or change it dynamically while the session is active.

**At session start:**

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :accept_edits
)
```

**Per-query override:**

```elixir
# Session starts in default mode
{:ok, session} = ClaudeCode.start_link(permission_mode: :default)

# Override to accept_edits for this specific query
session
|> ClaudeCode.stream("Refactor this module", permission_mode: :accept_edits)
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

**During streaming (dynamic change):**

Call `ClaudeCode.Session.set_permission_mode/2` to change the mode mid-session. The new mode takes effect immediately for all subsequent tool requests. This lets you start restrictive and loosen permissions as trust builds -- for example, switching to `:accept_edits` after reviewing Claude's initial approach.

```elixir
{:ok, session} = ClaudeCode.start_link(permission_mode: :default)

# Change mode dynamically mid-session
{:ok, _} = ClaudeCode.Session.set_permission_mode(session, :accept_edits)

# Subsequent queries use the new permission mode
session
|> ClaudeCode.stream("Now refactor the module")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

### Mode details

#### Accept edits mode (`:accept_edits`)

Auto-approves file operations so Claude can edit code without prompting. Other tools (like Bash commands that aren't filesystem operations) still require normal permissions.

**Auto-approved operations:**

- File edits (Edit, Write tools)
- Filesystem commands: `mkdir`, `touch`, `rm`, `mv`, `cp`

**Use when:** you trust Claude's edits and want faster iteration, such as during prototyping or when working in an isolated directory.

#### Don't ask mode (`:dont_ask`)

Converts any permission prompt into a denial. Tools pre-approved by `:allowed_tools`, settings.json allow rules, or a hook run as normal. Everything else is denied without calling `can_use_tool`.

**Use when:** you want a fixed, explicit tool surface for a headless agent and prefer a hard deny over prompting.

```elixir
{:ok, result} = ClaudeCode.query(
  "Summarize the project structure",
  allowed_tools: ["Read", "Glob", "Grep"],
  permission_mode: :dont_ask
)
```

#### Bypass permissions mode (`:bypass_permissions`)

Auto-approves all tool uses without prompts. Hooks still execute and can block operations if needed.

> **Warning:** Use with extreme caution. Claude has full system access in this mode. Only use in controlled environments where you trust all possible operations.
>
> `:allowed_tools` does not constrain this mode. Every tool is approved, not just the ones you listed. Deny rules (`:disallowed_tools`), explicit `ask` rules, and hooks are evaluated before the mode check and can still block a tool.

The Elixir SDK requires `allow_dangerously_skip_permissions: true` to enable this mode:

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :bypass_permissions,
  allow_dangerously_skip_permissions: true
)
```

For additional isolation, combine with the `:sandbox` option to restrict bash command execution:

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :bypass_permissions,
  allow_dangerously_skip_permissions: true,
  sandbox: %{
    "environment" => "docker",
    "container" => "my-sandbox"
  }
)
```

#### Plan mode (`:plan`)

Prevents tool execution entirely. Claude can analyze code and create plans but cannot make changes. Claude may use `AskUserQuestion` to clarify requirements before finalizing the plan. See [Handle approvals and user input](user-input.md#handle-clarifying-questions) for handling these prompts.

**Use when:** you want Claude to propose changes without executing them, such as during code review or when you need to approve changes before they're made.

```elixir
{:ok, result} = ClaudeCode.query(
  "How should we restructure the authentication module?",
  permission_mode: :plan,
  system_prompt: "Analyze the codebase and propose a refactoring plan."
)
```

## Related resources

For the other steps in the permission evaluation flow:

- [Handle approvals and user input](user-input.md) -- Interactive approval prompts and clarifying questions
- [Hooks](hooks.md) -- Run custom code at key points in the agent lifecycle
- [Permission rules](https://code.claude.com/docs/en/settings#permission-settings) -- Declarative allow/deny rules in settings
- [Secure Deployment](secure-deployment.md) -- Permission rules, sandboxing, and production security
- [MCP](mcp.md) -- Connect external tools via MCP servers
