# Permissions

Control how your agent uses tools with permission modes, hooks, and declarative allow/deny rules.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/permissions). Examples are adapted for Elixir.

---

The Elixir SDK provides permission controls to manage how Claude uses tools. Use permission modes and tool rules to define what is allowed automatically, and the `permission_prompt_tool` option to delegate decisions at runtime.

> This page covers permission modes and rules. To build interactive approval flows where users approve or deny tool requests at runtime, see [Handle approvals and user input](user-input.md).

## How permissions are evaluated

When Claude requests a tool, the SDK checks permissions in this order:

1. **Hooks** -- Run [hooks](hooks.md) first, which can allow, deny, or continue to the next step.
2. **Permission rules** -- Check declarative rules defined in settings (via the `:settings` option or settings files loaded by `:setting_sources`). `deny` rules block regardless of other rules, `allow` rules permit if matched, and `ask` rules prompt for approval. These declarative rules let you pre-approve, block, or require approval for specific tools without writing code.
3. **Permission mode** -- Apply the active [permission mode](#permission-modes) (`:default`, `:accept_edits`, `:bypass_permissions`, `:plan`, `:delegate`, `:dont_ask`).
4. **Permission prompt tool** -- If not resolved by rules or modes, call your `permission_prompt_tool` MCP tool for a decision.

This page focuses on **permission modes** (step 3), the static configuration that controls default behavior. For the other steps:

- **Hooks**: run custom code to allow, deny, or modify tool requests. See [Control execution with hooks](hooks.md).
- **Permission rules**: configure declarative allow/deny rules in settings. See [Secure Deployment](secure-deployment.md).
- **Permission prompt tool**: delegate permission decisions to an MCP tool at runtime. See [Handle approvals and user input](user-input.md).

## Permission modes

Permission modes provide global control over how Claude uses tools. Set the permission mode when starting a session, override it per query, or change it dynamically mid-session.

### Available modes

The SDK supports these permission modes:

| Mode                  | Description                  | Tool behavior                                                                         |
| :-------------------- | :--------------------------- | :------------------------------------------------------------------------------------ |
| `:default`            | Standard permission behavior | No auto-approvals; unmatched tools trigger your permission prompt tool or are rejected |
| `:accept_edits`       | Auto-accept file edits       | File edits and [filesystem operations](#accept-edits-mode-accept_edits) are automatically approved |
| `:bypass_permissions` | Bypass all permission checks | All tools run without permission prompts (use with caution)                            |
| `:plan`               | Planning mode                | No tool execution; Claude plans without making changes                                 |
| `:delegate`           | Delegate to permission tool  | All permission decisions are delegated to your `permission_prompt_tool`                |
| `:dont_ask`           | Deny unmatched tools         | Tools not explicitly allowed by rules are denied without prompting                     |

> **Warning:** When using `:bypass_permissions`, all subagents inherit this mode and it cannot be overridden. Subagents may have different system prompts and less constrained behavior than your main agent. Enabling `:bypass_permissions` grants them full, autonomous system access without any approval prompts.

### Set permission mode

You can set the permission mode at session start, override it per query, or change it dynamically while the session is active.

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

Call `ClaudeCode.set_permission_mode/2` to change the mode mid-session. The new mode takes effect immediately for all subsequent tool requests. This lets you start restrictive and loosen permissions as trust builds -- for example, switching to `:accept_edits` after reviewing Claude's initial approach.

```elixir
{:ok, session} = ClaudeCode.start_link(permission_mode: :default)

# Change mode dynamically mid-session
{:ok, _} = ClaudeCode.set_permission_mode(session, :accept_edits)

# Subsequent queries use the new permission mode
session
|> ClaudeCode.stream("Now refactor the module")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

### Mode details

#### Accept edits mode (`:accept_edits`)

Auto-approves file operations so Claude can edit code without prompting. Other tools (like Bash commands that are not filesystem operations) still require normal permissions.

**Auto-approved operations:**

- File edits (Edit, Write tools)
- Filesystem commands: `mkdir`, `touch`, `rm`, `mv`, `cp`

**Use when:** you trust Claude's edits and want faster iteration, such as during prototyping or when working in an isolated directory.

#### Bypass permissions mode (`:bypass_permissions`)

Auto-approves all tool uses without prompts. Hooks still execute and can block operations if needed.

> **Warning:** Use with extreme caution. Claude has full system access in this mode. Only use in controlled environments where you trust all possible operations.

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

Prevents tool execution entirely. Claude can analyze code and create plans but cannot make changes. Claude may use `AskUserQuestion` to clarify requirements before finalizing the plan. See [Handle approvals and user input](user-input.md) for handling these prompts.

**Use when:** you want Claude to propose changes without executing them, such as during code review or when you need to approve changes before they are made.

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
- [Secure Deployment](secure-deployment.md) -- Permission rules, sandboxing, and production security
- [MCP](mcp.md) -- Connect external tools via MCP servers
