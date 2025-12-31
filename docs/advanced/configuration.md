# Configuration Guide

ClaudeCode uses NimbleOptions for configuration validation. Options can be set at multiple levels with clear precedence rules.

## Option Precedence

Options are resolved in this order (highest to lowest priority):

1. **Query-level options** - Passed to `query/3` or `query_stream/3`
2. **Session-level options** - Passed to `start_link/1`
3. **Application config** - Set in `config/config.exs`
4. **Default values** - Built-in defaults

```elixir
# Application config (lowest priority)
config :claude_code, timeout: 300_000

# Session-level overrides app config
{:ok, session} = ClaudeCode.start_link(timeout: 120_000)

# Query-level overrides session
ClaudeCode.query(session, "Hello", timeout: 60_000)
```

## Session Options

All options for `ClaudeCode.start_link/1`:

### Authentication

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api_key` | string | `ANTHROPIC_API_KEY` env | Anthropic API key |
| `name` | atom | - | Register session with a name |

### Model Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `model` | string | "sonnet" | Claude model to use |
| `fallback_model` | string | - | Fallback if primary model fails |
| `system_prompt` | string | - | Override system prompt |
| `append_system_prompt` | string | - | Append to default system prompt |
| `max_turns` | integer | - | Limit conversation turns |

### Timeouts

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `timeout` | integer | 300_000 | Query timeout in milliseconds |

### Tool Control

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `allowed_tools` | list | - | Tools Claude can use |
| `disallowed_tools` | list | - | Tools Claude cannot use |
| `add_dir` | list | - | Additional accessible directories |
| `permission_mode` | atom | `:default` | Permission handling mode |

### Advanced

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `resume` | string | - | Session ID to resume |
| `mcp_config` | string | - | Path to MCP config file |
| `agents` | map | - | Custom agent configurations |
| `settings` | map/string | - | Team settings |
| `setting_sources` | list | - | Setting source priority |
| `tool_callback` | function | - | Called after tool executions |
| `include_partial_messages` | boolean | false | Enable character-level streaming |

## Query Options

Options that can be passed to `query/3` or `query_stream/3`:

| Option | Type | Description |
|--------|------|-------------|
| `timeout` | integer | Override session timeout |
| `system_prompt` | string | Override system prompt for this query |
| `append_system_prompt` | string | Append to system prompt |
| `max_turns` | integer | Limit turns for this query |
| `include_partial_messages` | boolean | Enable deltas for this query |

Note: `api_key` and `name` cannot be overridden at query time.

## Application Configuration

Set defaults in `config/config.exs`:

```elixir
config :claude_code,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "sonnet",
  timeout: 180_000,
  system_prompt: "You are a helpful assistant",
  allowed_tools: ["View"]
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :claude_code,
  timeout: 60_000,
  permission_mode: :accept_edits

# config/prod.exs
config :claude_code,
  timeout: 300_000,
  permission_mode: :default

# config/test.exs
config :claude_code,
  api_key: "test-key",
  timeout: 5_000
```

## Model Selection

```elixir
# Use a specific model
{:ok, session} = ClaudeCode.start_link(model: "opus")

# With fallback
{:ok, session} = ClaudeCode.start_link(
  model: "opus",
  fallback_model: "sonnet"
)
```

Available models: `"sonnet"`, `"opus"`, `"haiku"`, or full model IDs.

## System Prompts

```elixir
# Override completely
{:ok, session} = ClaudeCode.start_link(
  system_prompt: "You are an Elixir expert. Only discuss Elixir."
)

# Append to default
{:ok, session} = ClaudeCode.start_link(
  append_system_prompt: "Always format code with proper indentation."
)
```

## Tool Configuration

```elixir
# Allow specific tools
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["View", "Edit", "Bash(git:*)"]
)

# Disallow specific tools
{:ok, session} = ClaudeCode.start_link(
  disallowed_tools: ["Bash", "Write"]
)

# Additional directories
{:ok, session} = ClaudeCode.start_link(
  add_dir: ["/app/lib", "/app/test"]
)
```

## Custom Agents

Configure custom agents with specialized behaviors:

```elixir
agents = %{
  "code-reviewer" => %{
    "description" => "Expert code reviewer",
    "prompt" => "You review code for quality and best practices.",
    "tools" => ["View", "Grep", "Glob"],
    "model" => "sonnet"
  }
}

{:ok, session} = ClaudeCode.start_link(agents: agents)
```

See [Agents Guide](agents.md) for more details.

## Team Settings

```elixir
# From file path
{:ok, session} = ClaudeCode.start_link(
  settings: "/path/to/settings.json"
)

# From map (auto-encoded to JSON)
{:ok, session} = ClaudeCode.start_link(
  settings: %{
    "team_name" => "My Team",
    "preferences" => %{"theme" => "dark"}
  }
)

# Control setting sources
{:ok, session} = ClaudeCode.start_link(
  setting_sources: [:user, :project, :local]
)
```

## Validation Errors

Invalid options raise descriptive errors:

```elixir
{:ok, session} = ClaudeCode.start_link(timeout: "not a number")
# => ** (NimbleOptions.ValidationError) invalid value for :timeout option:
#       expected positive integer, got: "not a number"
```

## Next Steps

- [Permissions Guide](../guides/permissions.md) - Tool and permission control
- [Agents Guide](agents.md) - Custom agent configuration
- [Supervision Guide](supervision.md) - Production configuration
