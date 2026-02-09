# Secure Deployment

Harden your ClaudeCode deployment for production use.

## Sandbox Configuration

Isolate bash command execution with the `sandbox` option:

```elixir
{:ok, session} = ClaudeCode.start_link(
  sandbox: %{
    "environment" => "docker",
    "container" => "my-sandbox"
  }
)
```

The sandbox configuration is merged into the CLI's `--settings` flag as `{"sandbox": {...}}`.

## Permission Modes for Production

Choose the least-privileged permission mode for your use case:

| Mode | Use Case |
|------|----------|
| `:plan` | Read-only analysis, code review |
| `:dont_ask` | Automated pipelines where prompts can't be answered |
| `:accept_edits` | Supervised environments where file edits are expected |
| `:default` | Interactive use with a human in the loop |

```elixir
# Code review agent - read-only
{:ok, reviewer} = ClaudeCode.start_link(
  permission_mode: :plan,
  allowed_tools: ["Read", "Glob", "Grep"]
)

# CI/CD agent - rejects anything needing permission
{:ok, ci_agent} = ClaudeCode.start_link(
  permission_mode: :dont_ask,
  allowed_tools: ["Read", "Bash(mix:*)"]
)
```

## Least-Privilege Tool Access

Restrict tools to only what's needed:

```elixir
# Analysis-only agent
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Glob", "Grep"],
  add_dir: ["/app/src"]  # Only access source directory
)

# Build agent - limited bash commands
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Edit", "Bash(mix:*)", "Bash(git:*)"],
  disallowed_tools: ["Bash(rm:*)", "Bash(curl:*)"]
)
```

## API Key Management

Never hardcode API keys. Use environment variables:

```elixir
# config/runtime.exs
config :claude_code,
  api_key: System.fetch_env!("ANTHROPIC_API_KEY")
```

Or pass via the `env` option for per-session keys:

```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: System.fetch_env!("ANTHROPIC_API_KEY")
)
```

The SDK passes the API key via the `ANTHROPIC_API_KEY` environment variable to the CLI subprocess. It is never included in command-line arguments.

## Directory Access Control

Limit which directories Claude can access:

```elixir
{:ok, session} = ClaudeCode.start_link(
  cwd: "/app/workspace",
  add_dir: ["/app/shared/config"]
  # Claude can access /app/workspace (cwd) and /app/shared/config
)
```

## Cost Controls

Prevent runaway costs with budget limits:

```elixir
{:ok, session} = ClaudeCode.start_link(
  max_turns: 10,
  max_budget_usd: 1.00
)
```

If either limit is hit, the session returns an error result (`subtype: :error_max_turns` or `:error_max_budget_usd`).

## Audit Trail

Enable tool callbacks for a complete audit trail:

```elixir
{:ok, session} = ClaudeCode.start_link(
  tool_callback: fn event ->
    Logger.info("Tool #{event.name}: error=#{event.is_error}",
      tool_use_id: event.tool_use_id,
      input: event.input
    )
  end
)
```

## Disable Session Persistence

For ephemeral workloads, prevent session data from being saved to disk:

```elixir
{:ok, session} = ClaudeCode.start_link(
  no_session_persistence: true
)
```

## Production Checklist

- [ ] Use a restrictive `permission_mode` (`:plan`, `:dont_ask`, or `:accept_edits`)
- [ ] Set `allowed_tools` to only what's needed
- [ ] Set `max_turns` and `max_budget_usd` limits
- [ ] Store API keys in environment variables
- [ ] Enable `tool_callback` for auditing
- [ ] Use `cwd` and `add_dir` to limit file access
- [ ] Consider `sandbox` for bash isolation
- [ ] Use `no_session_persistence: true` for sensitive workloads
- [ ] Run sessions under `ClaudeCode.Supervisor` for fault tolerance

## Next Steps

- [Permissions](permissions.md) - Detailed permission configuration
- [Hosting](hosting.md) - OTP supervision and deployment
- [Cost Tracking](cost-tracking.md) - Usage monitoring
