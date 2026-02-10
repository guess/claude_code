# Handling Permissions

Control how your agent uses tools with permission modes and declarative allow/deny rules.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/permissions). Examples are adapted for Elixir.

---

The Elixir SDK provides permission controls to manage how Claude uses tools. Use permission modes and tool rules to define what is allowed automatically, and the `permission_prompt_tool` option to delegate decisions at runtime.

> This page covers permission modes and tool rules. To build interactive approval flows where users approve or deny tool requests at runtime, see [Handle approvals and user input](user-input.md).

## How permissions are evaluated

When Claude requests a tool, the SDK checks permissions in this order:

1. **Permission rules** -- Check declarative rules defined in settings (via the `:settings` option or settings files loaded by `:setting_sources`). `deny` rules block regardless of other rules, `allow` rules permit if matched, and `ask` rules prompt for approval.
2. **Permission mode** -- Apply the active permission mode (`:default`, `:accept_edits`, `:bypass_permissions`, etc.).
3. **Permission prompt tool** -- If not resolved by rules or modes, call your `permission_prompt_tool` MCP tool for a decision.

This page focuses on **permission modes** (step 2), the static configuration that controls default behavior. For the other steps:

- **Permission rules**: configure declarative allow/deny rules in settings. See [Secure Deployment](secure-deployment.md).
- **Permission prompt tool**: delegate permission decisions to an MCP tool. See [Permission delegation](#permission-delegation).

## Permission modes

Permission modes provide global control over how Claude uses tools. Set the permission mode when starting a session or override it per query.

### Available modes

The SDK supports these permission modes:

| Mode                  | Description                                     | Tool behavior                                                                          |
| :-------------------- | :---------------------------------------------- | :------------------------------------------------------------------------------------- |
| `:default`            | Standard permission behavior                    | No auto-approvals; unmatched tools trigger your permission prompt tool or are rejected |
| `:accept_edits`       | Auto-accept file edits                          | File edits and filesystem operations are automatically approved                        |
| `:bypass_permissions` | Bypass all permission checks                    | All tools run without permission prompts (use with caution)                            |
| `:plan`               | Planning mode                                   | No tool execution; Claude plans without making changes                                 |
| `:dont_ask`           | Reject operations that would require permission | Tools needing approval are silently denied                                             |
| `:delegate`           | Delegate to MCP tool                            | Permission decisions are forwarded to the `permission_prompt_tool`                     |

> **Warning:** When using `:bypass_permissions`, all subagents inherit this mode and it cannot be overridden. Subagents may have different system prompts and less constrained behavior than your main agent. Enabling `:bypass_permissions` grants them full, autonomous system access without any approval prompts.

### Set permission mode

You can set the permission mode at session start, or override it for individual queries.

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

### Mode details

#### Accept edits mode (`:accept_edits`)

Auto-approves file operations so Claude can edit code without prompting. Other tools (like Bash commands that are not filesystem operations) still require normal permissions.

**Auto-approved operations:**

- File edits (Edit, Write tools)
- Filesystem commands: `mkdir`, `touch`, `rm`, `mv`, `cp`

**Use when:** you trust Claude's edits and want faster iteration, such as during prototyping or when working in an isolated directory.

```elixir
{:ok, result} = ClaudeCode.query("Add error handling to lib/my_app/api.ex",
  permission_mode: :accept_edits
)
```

#### Bypass permissions mode (`:bypass_permissions`)

Auto-approves all tool uses without prompts. Requires `allow_dangerously_skip_permissions: true`.

> **Warning:** Use with extreme caution. Claude has full system access in this mode. Only use in controlled, sandboxed environments where you trust all possible operations and there is no internet access.

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

The `:sandbox` option is merged into the `--settings` flag and configures how bash commands are isolated. See [Secure Deployment](secure-deployment.md) for details.

#### Plan mode (`:plan`)

Prevents tool execution entirely. Claude can analyze code and create plans but cannot make changes.

**Use when:** you want Claude to propose changes without executing them, such as during code review or when you need to approve changes before they are made.

```elixir
{:ok, result} = ClaudeCode.query(
  "How should we restructure the authentication module?",
  permission_mode: :plan,
  system_prompt: "Analyze the codebase and propose a refactoring plan."
)
```

#### Don't ask mode (`:dont_ask`)

Silently rejects any tool use that would normally require permission. Unlike `:plan` mode, which prevents all tool execution, `:dont_ask` allows tools that are pre-approved but rejects anything that would trigger a permission prompt.

**Use when:** you want the agent to operate autonomously without blocking on permission prompts, and you prefer denied operations over interactive approval.

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :dont_ask
)
```

## Tool control

In addition to permission modes, you can restrict which tools Claude has access to using allow and deny lists.

### Allowed tools

Restrict Claude to a specific set of tools:

```elixir
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Glob", "Grep"]
)
```

Supports glob patterns for granular control:

```elixir
# Only allow git commands via Bash
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Bash(git:*)"]
)

# Allow all MCP tools from a specific server
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "mcp__my_server__*"]
)
```

### Disallowed tools

Block specific tools while allowing everything else:

```elixir
{:ok, session} = ClaudeCode.start_link(
  disallowed_tools: ["Bash", "Write"]
)
```

### Available tools set

Control which built-in tools are available with the `:tools` option. This is different from `:allowed_tools` -- it controls the base set of tools the CLI loads, while `:allowed_tools` filters what the agent can actually use.

```elixir
# Use all default tools
{:ok, session} = ClaudeCode.start_link(tools: :default)

# Only load specific tools from the built-in set
{:ok, session} = ClaudeCode.start_link(tools: ["Bash", "Read", "Edit"])

# Disable all built-in tools (useful with MCP-only setups)
{:ok, session} = ClaudeCode.start_link(tools: [])
```

### Per-query overrides

Tool restrictions can be changed per query. Query options take precedence over session defaults:

```elixir
# Session allows Read and Write
{:ok, session} = ClaudeCode.start_link(allowed_tools: ["Read", "Write"])

# But this specific query is read-only
session
|> ClaudeCode.stream("Review this code", allowed_tools: ["Read"])
|> ClaudeCode.Stream.text_content()
|> Enum.join()
```

## Permission delegation

The `:delegate` permission mode forwards permission decisions to an MCP tool specified by `permission_prompt_tool`. This is useful when you want to implement custom approval logic, such as prompting a user through a web UI or applying policy rules from an external service.

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :delegate,
  permission_prompt_tool: "mcp__my_server__approve_tool",
  mcp_config: "/path/to/mcp-config.json"
)
```

When Claude requests a tool that needs approval, the SDK calls the specified MCP tool with the tool name and input, and expects a response indicating whether to allow or deny the operation.

## Permission denials

When tools are denied due to permission settings, the `ClaudeCode.Message.ResultMessage` tracks them in the `permission_denials` field. Each denial is a map with `:tool_name`, `:tool_use_id`, and `:tool_input` keys.

```elixir
alias ClaudeCode.Message.ResultMessage

session
|> ClaudeCode.stream("Edit some files")
|> ClaudeCode.Stream.final_result()
|> case do
  %ResultMessage{permission_denials: denials} when denials != [] ->
    IO.puts("#{length(denials)} tool(s) were denied:")

    Enum.each(denials, fn denial ->
      IO.puts("  - #{denial.tool_name} (#{inspect(denial.tool_input)})")
    end)

  %ResultMessage{} ->
    IO.puts("All tools were approved.")
end
```

## Read-only agent example

Combine `:plan` mode with `:allowed_tools` to create an agent that can only read and analyze code:

```elixir
{:ok, reviewer} = ClaudeCode.start_link(
  name: :code_reviewer,
  system_prompt: "You are a code reviewer. Analyze code and suggest improvements.",
  permission_mode: :plan,
  allowed_tools: ["Read", "Glob", "Grep"]
)

:code_reviewer
|> ClaudeCode.stream("Review the error handling in lib/my_app/api.ex")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

## Confirming active permissions

The `ClaudeCode.Message.SystemMessage` emitted at session start (subtype `:init`) includes the active `permission_mode` and the list of available `tools`. Use this to verify your configuration:

```elixir
alias ClaudeCode.Message.SystemMessage

session
|> ClaudeCode.stream("Hello")
|> Enum.each(fn
  %SystemMessage{subtype: :init, permission_mode: mode, tools: tools} ->
    IO.puts("Permission mode: #{mode}")
    IO.puts("Available tools: #{Enum.join(tools, ", ")}")

  _ ->
    :ok
end)
```

## Next steps

- [Secure Deployment](secure-deployment.md) -- Sandboxing, permission rules, and production security
- [User Input](user-input.md) -- Handle approvals and multi-turn interactions
- [Hooks](hooks.md) -- Monitor tool execution with callbacks
- [MCP](mcp.md) -- Connect external tools via MCP servers
