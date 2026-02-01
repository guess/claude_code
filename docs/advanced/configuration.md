# Configuration Guide

ClaudeCode uses NimbleOptions for configuration validation. Options can be set at multiple levels with clear precedence rules.

## Option Precedence

Options are resolved in this order (highest to lowest priority):

1. **Query-level options** - Passed to `query/3` or `stream/3`
2. **Session-level options** - Passed to `start_link/1`
3. **Application config** - Set in `config/config.exs`
4. **Default values** - Built-in defaults

```elixir
# Application config (lowest priority)
config :claude_code, timeout: 300_000

# Session-level overrides app config
{:ok, session} = ClaudeCode.start_link(timeout: 120_000)

# Query-level overrides session
ClaudeCode.stream(session, "Hello", timeout: 60_000)
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
| `max_budget_usd` | number | - | Maximum dollar amount to spend on API calls |
| `agent` | string | - | Agent name for the session |
| `betas` | list | - | Beta headers for API requests |
| `max_thinking_tokens` | integer | - | Maximum tokens for thinking blocks |

### Timeouts

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `timeout` | integer | 300_000 | Query timeout in milliseconds |

### Tool Control

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tools` | atom/list | - | Available tools: `:default`, `[]`, or list of names |
| `allowed_tools` | list | - | Tools Claude can use |
| `disallowed_tools` | list | - | Tools Claude cannot use |
| `add_dir` | list | - | Additional accessible directories |
| `permission_mode` | atom | `:default` | Permission handling mode |

### Advanced

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `resume` | string | - | Session ID to resume |
| `fork_session` | boolean | false | Create new session ID when resuming |
| `continue` | boolean | false | Continue most recent conversation in current directory |
| `mcp_config` | string | - | Path to MCP config file |
| `strict_mcp_config` | boolean | false | Only use MCP servers from explicit config |
| `agents` | map | - | Custom agent configurations |
| `settings` | map/string | - | Team settings |
| `setting_sources` | list | - | Setting source priority |
| `tool_callback` | function | - | Called after tool executions |
| `include_partial_messages` | boolean | false | Enable character-level streaming |
| `output_format` | map | - | Structured output format (see Structured Outputs section) |
| `plugins` | list | - | Plugin configurations to load (paths or maps with type: :local) |

## Query Options

Options that can be passed to `stream/3`:

| Option | Type | Description |
|--------|------|-------------|
| `timeout` | integer | Override session timeout |
| `system_prompt` | string | Override system prompt for this query |
| `append_system_prompt` | string | Append to system prompt |
| `max_turns` | integer | Limit turns for this query |
| `max_budget_usd` | number | Maximum dollar amount for this query |
| `agent` | string | Agent to use for this query |
| `betas` | list | Beta headers for this query |
| `max_thinking_tokens` | integer | Maximum tokens for thinking blocks |
| `tools` | list | Available tools for this query |
| `allowed_tools` | list | Allowed tools for this query |
| `disallowed_tools` | list | Disallowed tools for this query |
| `output_format` | map | Structured output format for this query |
| `plugins` | list | Plugin configurations for this query |
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

### CLI Configuration

The SDK can automatically manage the Claude CLI binary:

```elixir
config :claude_code,
  cli_version: "latest",           # Version to install ("latest" or "2.1.29")
  cli_path: nil,                    # Explicit path to CLI binary (highest priority)
  cli_dir: nil                      # Directory for downloaded binary (default: priv/bin/)
```

**Binary resolution order:**
1. `:cli_path` option (explicit override)
2. Application config `:cli_path`
3. Bundled binary in `cli_dir` (default: priv/bin/)
4. System PATH
5. Common installation locations (~/.local/bin, ~/.npm-global/bin, etc.)

**Install the CLI:**
```bash
mix claude_code.install              # Install latest version
mix claude_code.install --version 2.1.29  # Install specific version
mix claude_code.install --if-missing # Only if not present
mix claude_code.install --force      # Force reinstall
```

**For releases:**
```elixir
# Option 1: Pre-install during release build
# (Run mix claude_code.install before building the release)

# Option 2: Configure writable directory for runtime download
config :claude_code, cli_dir: "/var/lib/claude_code"

# Option 3: Rely on system-installed CLI in PATH
# (No configuration needed, just ensure 'claude' is in PATH)
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

## Cost Control

```elixir
# Limit spending per query
session
|> ClaudeCode.stream("Complex analysis task", max_budget_usd: 5.00)
|> Stream.run()

# Set a session-wide budget limit
{:ok, session} = ClaudeCode.start_link(
  max_budget_usd: 25.00
)
```

## Structured Outputs

Use the `:output_format` option with a JSON Schema to get validated structured responses:

```elixir
schema = %{
  "type" => "object",
  "properties" => %{
    "name" => %{"type" => "string"},
    "age" => %{"type" => "integer"},
    "skills" => %{"type" => "array", "items" => %{"type" => "string"}}
  },
  "required" => ["name", "age"]
}

session
|> ClaudeCode.stream("Extract person info from: John is 30 and knows Elixir",
     output_format: %{type: :json_schema, schema: schema})
|> ClaudeCode.Stream.text_content()
|> Enum.join()
```

The `:output_format` option accepts a map with:
- `:type` - Currently only `:json_schema` is supported
- `:schema` - A JSON Schema map defining the expected structure

## Tool Configuration

```elixir
# Use all default tools
{:ok, session} = ClaudeCode.start_link(tools: :default)

# Specify available tools (subset of built-in)
{:ok, session} = ClaudeCode.start_link(
  tools: ["Bash", "Edit", "Read"]
)

# Disable all tools
{:ok, session} = ClaudeCode.start_link(tools: [])

# Allow specific tools with patterns
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

## MCP Server Control

Claude Code can connect to MCP (Model Context Protocol) servers for additional tools. By default, it uses globally configured MCP servers. Use `strict_mcp_config` to control this:

```elixir
# No tools at all (no built-in tools, no MCP servers)
{:ok, session} = ClaudeCode.start_link(
  tools: [],
  strict_mcp_config: true
)
# tools: [], mcp_servers: []

# Built-in tools only (ignore global MCP servers)
{:ok, session} = ClaudeCode.start_link(
  tools: :default,
  strict_mcp_config: true
)
# tools: ["Task", "Bash", "Read", "Edit", ...], mcp_servers: []

# Default behavior (built-in tools + global MCP servers)
{:ok, session} = ClaudeCode.start_link()
# tools: ["Task", "Bash", ..., "mcp__memory__*", "mcp__github__*", ...]
# mcp_servers: [%{name: "memory", ...}, %{name: "github", ...}]

# Specific MCP servers only (no global config)
{:ok, session} = ClaudeCode.start_link(
  strict_mcp_config: true,
  mcp_servers: %{
    "my-tools" => %{command: "npx", args: ["my-mcp-server"]}
  }
)
```

### Using Hermes MCP Modules

You can use Elixir-based MCP servers built with [Hermes MCP](https://hex.pm/packages/hermes_mcp):

```elixir
{:ok, session} = ClaudeCode.start_link(
  strict_mcp_config: true,
  mcp_servers: %{
    "my-tools" => MyApp.MCPServer,
    "custom" => %{module: MyApp.MCPServer, env: %{"DEBUG" => "1"}}
  }
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

## Plugins

Load custom plugins to extend Claude's capabilities:

```elixir
# From a directory path
{:ok, session} = ClaudeCode.start_link(
  plugins: ["./my-plugin"]
)

# With explicit type (currently only :local is supported)
{:ok, session} = ClaudeCode.start_link(
  plugins: [
    %{type: :local, path: "./my-plugin"},
    "./another-plugin"
  ]
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
