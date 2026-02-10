# MCP (Model Context Protocol)

Configure MCP servers to extend your agent with external tools. Covers transport types, tool permissions, authentication, and error handling.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/mcp). Examples are adapted for Elixir.

> **Partial implementation:** In-process SDK MCP servers via `ClaudeCode.Tool.Server` are not yet implemented. All other MCP patterns (stdio, HTTP/SSE, Hermes modules, config files) are fully supported today.

The [Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) is an open standard for connecting AI agents to external tools and data sources. With MCP, your agent can query databases, integrate with APIs like Slack and GitHub, and connect to other services without writing custom tool implementations.

MCP servers can run as local processes (stdio), connect over HTTP/SSE, or execute directly within your Elixir application using in-process tools.

For building your own custom tools, see the [Custom Tools](custom-tools.md) guide.

## Quickstart

This example connects to an external MCP server and uses `:allowed_tools` with a wildcard to permit all tools from the server:

```elixir
{:ok, result} = ClaudeCode.query(
  "Use the docs MCP server to explain what hooks are in Claude Code",
  mcp_servers: %{
    "claude-code-docs" => %{
      type: "http",
      url: "https://code.claude.com/docs/mcp"
    }
  },
  allowed_tools: ["mcp__claude-code-docs__*"]
)
```

## Add an MCP server

You can configure MCP servers in code when calling `ClaudeCode.query/2` or `ClaudeCode.start_link/1`, or in a `.mcp.json` file that the CLI loads automatically.

### In code

Pass MCP servers directly in the `:mcp_servers` option:

```elixir
{:ok, result} = ClaudeCode.query("List files in my project",
  mcp_servers: %{
    "filesystem" => %{
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/projects"]
    }
  },
  allowed_tools: ["mcp__filesystem__*"]
)
```

### From a config file

Create a `.mcp.json` file at your project root. The CLI loads this automatically:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/projects"]
    }
  }
}
```

Or point to a config file explicitly with the `:mcp_config` option:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_config: "/path/to/mcp-config.json"
)
```

## Allow MCP tools

MCP tools require explicit permission before Claude can use them. Without permission, Claude sees that tools are available but cannot call them.

### Tool naming convention

MCP tools follow the naming pattern `mcp__<server-name>__<tool-name>`. For example, a GitHub server named `"github"` with a `list_issues` tool becomes `mcp__github__list_issues`.

### Grant access with allowed_tools

Use the `:allowed_tools` option to specify which MCP tools Claude can use:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"github" => github_config, "db" => db_config},
  allowed_tools: [
    "mcp__github__*",              # All tools from the github server
    "mcp__db__query",              # Only the query tool from db server
    "Read"                          # Built-in tools can be mixed in
  ]
)
```

Wildcards (`*`) let you allow all tools from a server without listing each one individually.

### Alternative: change the permission mode

Instead of listing allowed tools, you can change the permission mode to grant broader access:

- `:accept_edits` -- Automatically approves tool usage (still prompts for destructive operations)
- `:bypass_permissions` -- Skips all safety prompts. Use with caution. Requires `:allow_dangerously_skip_permissions`.

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  permission_mode: :accept_edits  # No need for allowed_tools
)
```

See [Permissions](permissions.md) for more details on permission modes.

### Discover available tools

Inspect the system init message at the start of each session to see what tools an MCP server provides:

```elixir
alias ClaudeCode.Message.SystemMessage

session
|> ClaudeCode.stream("List files")
|> ClaudeCode.Stream.filter_type(:system)
|> Enum.take(1)
|> case do
  [%SystemMessage{tools: tools}] ->
    mcp_tools = Enum.filter(tools, &String.starts_with?(&1, "mcp__"))
    IO.inspect(mcp_tools, label: "Available MCP tools")

  _ ->
    IO.puts("No system message received")
end
```

## Transport types

MCP servers communicate with your agent using different transport protocols:

- If the docs give you a **command to run** (like `npx @modelcontextprotocol/server-github`), use stdio
- If the docs give you a **URL**, use HTTP or SSE
- If you want to build tools **in Elixir**, see the [Custom Tools](custom-tools.md) guide

### stdio servers

Local processes that communicate via stdin/stdout. Use this for MCP servers you run on the same machine:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "github" => %{
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-github"],
      env: %{
        "GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN")
      }
    }
  },
  allowed_tools: ["mcp__github__list_issues", "mcp__github__search_issues"]
)
```

### HTTP/SSE servers

Use HTTP or SSE for cloud-hosted MCP servers and remote APIs:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "remote-api" => %{
      type: "sse",
      url: "https://api.example.com/mcp/sse",
      headers: %{
        "Authorization" => "Bearer #{System.get_env("API_TOKEN")}"
      }
    }
  },
  allowed_tools: ["mcp__remote-api__*"]
)
```

For HTTP (non-streaming), use `"type" => "http"` instead of `"sse"`.

### In-process SDK servers

> **Not yet implemented.** This transport type requires the planned `ClaudeCode.Tool.Server` API.

Define custom tools that run in the same BEAM process, with access to Ecto repos, GenServers, and caches. See the [Custom Tools](custom-tools.md) guide for the full API and examples.

```elixir
{:ok, result} = ClaudeCode.query("Find user alice@example.com",
  mcp_servers: %{"my-tools" => MyApp.Tools},
  allowed_tools: ["mcp__my-tools__*"]
)
```

### Hermes MCP servers

Define tools using [Hermes MCP](https://hexdocs.pm/hermes_mcp) modules. The SDK spawns the module as a stdio subprocess automatically. See the [Custom Tools](custom-tools.md) guide for defining Hermes tool components.

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  allowed_tools: ["mcp__my-tools__*"]
)
```

Pass custom environment variables to Hermes subprocesses with the `%{module: ..., env: ...}` form:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "db-tools" => %{
      module: MyApp.DBTools,
      env: %{"DATABASE_URL" => System.get_env("DATABASE_URL")}
    }
  }
)
```

### Mixing server types

All transport types work together in a single session:

```elixir
db_url = System.get_env("DATABASE_URL")

{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    # In-process (runs in your BEAM VM)
    "app-tools" => MyApp.Tools,
    # Hermes module (spawns as subprocess)
    "db-tools" => %{module: MyApp.DBServer, env: %{"DATABASE_URL" => db_url}},
    # External Node.js server
    "browser" => %{command: "npx", args: ["@playwright/mcp@latest"]},
    # Remote HTTP server
    "docs" => %{type: "http", url: "https://code.claude.com/docs/mcp"}
  },
  allowed_tools: ["mcp__app-tools__*", "mcp__db-tools__*", "mcp__browser__*", "mcp__docs__*"]
)
```

## Strict MCP configuration

By default, the CLI may load MCP servers from global configurations (such as `~/.claude/settings.json`). To ignore these and only use explicitly provided servers, set `:strict_mcp_config` to `true`:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  strict_mcp_config: true,
  allowed_tools: ["mcp__my-tools__*"]
)
```

This is especially useful in production deployments where you want deterministic tool availability.

## MCP tool search

When you have many MCP tools configured, tool definitions can consume a significant portion of your context window. MCP tool search solves this by dynamically loading tools on-demand instead of preloading all of them.

### How it works

Tool search runs in auto mode by default. It activates when your MCP tool descriptions would consume more than 10% of the context window. When triggered:

1. MCP tools are marked with `defer_loading: true` rather than loaded into context upfront
2. Claude uses a search tool to discover relevant MCP tools when needed
3. Only the tools Claude actually needs are loaded into context

### Configure tool search

Control tool search behavior with the `ENABLE_TOOL_SEARCH` environment variable via the `:env` option:

| Value | Behavior |
|---|---|
| `auto` | Activates when MCP tools exceed 10% of context (default) |
| `auto:5` | Activates at 5% threshold (customize the percentage) |
| `true` | Always enabled |
| `false` | Disabled, all MCP tools loaded upfront |

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"large-server" => large_server_config},
  env: %{"ENABLE_TOOL_SEARCH" => "auto:5"},
  allowed_tools: ["mcp__large-server__*"]
)
```

## Authentication

Most MCP servers require authentication to access external services. Pass credentials through environment variables or HTTP headers in the server configuration.

### Environment variables

Use the `env` field to pass API keys, tokens, and other credentials:

```elixir
# External stdio server
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "github" => %{
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-github"],
      env: %{"GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN")}
    }
  },
  allowed_tools: ["mcp__github__list_issues"]
)

# Hermes MCP module
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "db-tools" => %{
      module: MyApp.DBTools,
      env: %{"DATABASE_URL" => System.get_env("DATABASE_URL")}
    }
  }
)
```

For in-process tools (`ClaudeCode.Tool.Server`), credentials are accessed directly via `System.get_env/1` or application config since the tools run in your application process.

In config files, use the `${VAR_NAME}` syntax to expand environment variables at runtime:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### HTTP headers for remote servers

For HTTP and SSE servers, pass authentication headers directly in the server configuration:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "secure-api" => %{
      type: "http",
      url: "https://api.example.com/mcp",
      headers: %{
        "Authorization" => "Bearer #{System.get_env("API_TOKEN")}"
      }
    }
  },
  allowed_tools: ["mcp__secure-api__*"]
)
```

## Permission delegation

Delegate permission decisions to an MCP tool instead of handling them in the SDK. This is useful when you want a custom server to control which operations Claude is allowed to perform:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"permissions" => MyApp.PermissionServer},
  permission_mode: :delegate,
  permission_prompt_tool: "mcp__permissions__check_permission",
  allowed_tools: ["mcp__permissions__*"]
)
```

The `:permission_prompt_tool` option specifies the MCP tool that the CLI calls when Claude requests permission to use a tool. See [Permissions](permissions.md) for details on permission modes.

## Examples

### List issues from a GitHub repository

This example connects to the GitHub MCP server to list recent issues. It includes message inspection to verify the MCP connection and tool calls.

Before running, create a [GitHub personal access token](https://github.com/settings/tokens) with `repo` scope:

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
```

```elixir
alias ClaudeCode.Message.{SystemMessage, AssistantMessage, ResultMessage}
alias ClaudeCode.Content.ToolUseBlock

{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "github" => %{
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-github"],
      env: %{"GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN")}
    }
  },
  allowed_tools: ["mcp__github__list_issues"]
)

session
|> ClaudeCode.stream("List the 3 most recent issues in anthropics/claude-code")
|> Enum.each(fn
  %SystemMessage{tools: tools} ->
    mcp_tools = Enum.filter(tools, &String.starts_with?(&1, "mcp__github__"))
    IO.inspect(mcp_tools, label: "GitHub MCP tools")

  %AssistantMessage{message: %{content: blocks}} ->
    for %ToolUseBlock{name: name} <- blocks,
        String.starts_with?(name, "mcp__") do
      IO.puts("MCP tool called: #{name}")
    end

  %ResultMessage{result: result, is_error: false} ->
    IO.puts(result)

  _ ->
    :ok
end)
```

### Query a database

This example uses the Postgres MCP server to query a database. The agent automatically discovers the schema, writes SQL, and returns results:

```elixir
connection_string = System.get_env("DATABASE_URL")

{:ok, result} = ClaudeCode.query(
  "How many users signed up last week? Break it down by day.",
  mcp_servers: %{
    "postgres" => %{
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-postgres", connection_string]
    }
  },
  allowed_tools: ["mcp__postgres__query"]
)
```

## Error handling

MCP servers can fail to connect for various reasons: the server process might not be installed, credentials might be invalid, or a remote server might be unreachable.

The SDK emits a `ClaudeCode.Message.SystemMessage` with subtype `:init` at the start of each query. Inspect it to detect connection failures before the agent starts working:

```elixir
alias ClaudeCode.Message.{SystemMessage, ResultMessage}

session
|> ClaudeCode.stream("Process data")
|> Enum.each(fn
  %SystemMessage{subtype: :init} = msg ->
    IO.inspect(msg, label: "System init")

  %ResultMessage{is_error: true, subtype: subtype} ->
    IO.puts("Execution failed: #{subtype}")

  _ ->
    :ok
end)
```

For errors inside tool handlers (tool execution errors), see the [Custom Tools error handling](custom-tools.md#error-handling) section.

## Troubleshooting

### Server shows failed status

Check the init message to see which servers failed to connect. Common causes:

- **Missing environment variables** -- Ensure required tokens and credentials are set. For stdio servers, check that the `env` map matches what the server expects.
- **Server not installed** -- For `npx` commands, verify the package exists and Node.js is in your PATH.
- **Invalid connection string** -- For database servers, verify the connection string format and that the database is accessible.
- **Network issues** -- For remote HTTP/SSE servers, check that the URL is reachable and any firewalls allow the connection.

### Tools not being called

If Claude sees tools but does not use them, check that you have granted permission with `:allowed_tools` or by changing the `:permission_mode`:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  allowed_tools: ["mcp__my-tools__*"]  # Required for Claude to use the tools
)
```

### Connection timeouts

The MCP protocol has a default timeout of 60 seconds for server connections. If your server takes longer to start, the connection will fail. Consider:

- Using a lighter-weight server if available
- Pre-warming the server before starting your agent
- Checking server logs for slow initialization causes

## Related resources

- [Custom Tools](custom-tools.md) -- Build in-process tools and Hermes MCP servers
- [Permissions](permissions.md) -- Control which MCP tools your agent can use
- [Subagents](subagents.md) -- Define specialized agents with tool access
- [MCP server directory](https://github.com/modelcontextprotocol/servers) -- Browse available MCP servers
- [MCP specification](https://modelcontextprotocol.io) -- The full MCP protocol specification
