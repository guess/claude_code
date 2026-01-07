# Permissions Guide

ClaudeCode provides several options to control what actions Claude can perform during a session.

## Permission Modes

The `permission_mode` option controls how Claude handles permission requests:

```elixir
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :accept_edits
)
```

| Mode | Description |
|------|-------------|
| `:default` | CLI prompts for permission on sensitive operations |
| `:accept_edits` | Automatically accept file edit permissions |
| `:bypass_permissions` | Skip all permission prompts (use with caution) |

## Tool Restrictions

Control which tools Claude can use with `allowed_tools` and `disallowed_tools`:

```elixir
# Allow only specific tools
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["View", "Edit"]
)

# Allow tools with patterns
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["View", "Bash(git:*)"]  # Only git commands in Bash
)

# Disallow specific tools
{:ok, session} = ClaudeCode.start_link(
  disallowed_tools: ["Bash", "Edit"]
)
```

### Common Tool Names

- `View` - Read files
- `Edit` - Modify files
- `Write` - Create new files
- `Bash` - Execute shell commands
- `Glob` - Search for files
- `Grep` - Search file contents

### Tool Patterns

Use patterns to allow subsets of tool functionality:

```elixir
# Only allow git commands
allowed_tools: ["Bash(git:*)"]

# Only allow npm and git
allowed_tools: ["Bash(git:*)", "Bash(npm:*)"]
```

## Directory Access

Restrict which directories Claude can access:

```elixir
{:ok, session} = ClaudeCode.start_link(
  add_dir: ["/path/to/allowed/directory"]
)
```

## Security Considerations

1. **Production environments**: Use `permission_mode: :accept_edits` or stricter
2. **Untrusted input**: Always restrict tools when processing user-provided prompts
3. **File access**: Use `add_dir` to limit directory access
4. **Shell commands**: Use `allowed_tools: ["Bash(git:*)"]` patterns to restrict commands

## Example: Restricted Code Review

```elixir
# Safe configuration for automated code review
{:ok, session} = ClaudeCode.start_link(
  permission_mode: :default,
  allowed_tools: ["View", "Glob", "Grep"],  # Read-only tools
  add_dir: ["/app/src"]  # Only access source directory
)

review =
  session
  |> ClaudeCode.stream("Review the code for security issues")
  |> ClaudeCode.Stream.text_content()
  |> Enum.join()
```

## Next Steps

- [Configuration Guide](../advanced/configuration.md) - All configuration options
- [Tool Callbacks](../integration/tool-callbacks.md) - Monitor tool usage
