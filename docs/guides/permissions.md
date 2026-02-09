# Permissions

Control what tools Claude can use and how permission prompts are handled.

## Permission Modes

Set the permission mode when starting a session:

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :default
)
```

| Mode | Description |
|------|-------------|
| `:default` | Prompt the user for dangerous operations. |
| `:accept_edits` | Auto-accept file edits, prompt for other dangerous operations. |
| `:plan` | Read-only mode. Claude can only read files and think. |
| `:bypass_permissions` | Skip all permission checks. **Requires** `allow_dangerously_skip_permissions: true`. |
| `:dont_ask` | Reject operations that would require permission. |
| `:delegate` | Delegate permission decisions to an MCP tool (see `permission_prompt_tool:`). |

### Bypass Permissions (Sandboxed Environments)

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :bypass_permissions,
  allow_dangerously_skip_permissions: true
)
```

> **Warning**: Only use `:bypass_permissions` in sandboxed environments with no internet access. This disables all safety checks.

## Tool Control

### Allowed Tools

Restrict Claude to a specific set of tools:

```elixir
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Glob", "Grep"]
)
```

Supports glob patterns for granular control:

```elixir
# Only allow git commands via Bash
allowed_tools: ["Read", "Bash(git:*)"]

# Allow all MCP tools from a specific server
allowed_tools: ["Read", "mcp__my_server__*"]
```

### Disallowed Tools

Block specific tools while allowing everything else:

```elixir
{:ok, session} = ClaudeCode.start_link(
  disallowed_tools: ["Bash", "Write"]
)
```

### Available Tools Set

Control the set of built-in tools available:

```elixir
# Use all default tools
{:ok, session} = ClaudeCode.start_link(tools: :default)

# Only specific tools from the built-in set
{:ok, session} = ClaudeCode.start_link(tools: ["Bash", "Read", "Edit"])

# Disable all built-in tools (useful with MCP-only setups)
{:ok, session} = ClaudeCode.start_link(tools: [])
```

### Per-Query Overrides

Tool restrictions can be changed per query:

```elixir
# Session allows Read and Write
{:ok, session} = ClaudeCode.start_link(allowed_tools: ["Read", "Write"])

# But this specific query is read-only
session
|> ClaudeCode.stream("Review this code", allowed_tools: ["Read"])
|> ClaudeCode.Stream.text_content()
|> Enum.join()
```

## Read-Only Agent Example

Create an agent that can only read and analyze code:

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

## Permission Denials

When tools are denied due to permission settings, the `ResultMessage` tracks them:

```elixir
session
|> ClaudeCode.stream("Edit some files")
|> Enum.each(fn
  %ClaudeCode.Message.ResultMessage{permission_denials: denials} when denials != [] ->
    Enum.each(denials, fn denial ->
      IO.puts("Denied: #{denial.tool_name} (#{inspect(denial.tool_input)})")
    end)

  _ -> :ok
end)
```

## Next Steps

- [Secure Deployment](secure-deployment.md) - Sandboxing and production security
- [User Input](user-input.md) - Multi-turn interactions and interrupts
