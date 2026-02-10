# MCP (Model Context Protocol)

Connect to external tools with MCP servers. Covers transport types, Hermes MCP integration, tool permissions, authentication, and error handling.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/mcp). Examples are adapted for Elixir.

The [Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) is an open standard for connecting AI agents to external tools and data sources. With MCP, your agent can query databases, integrate with APIs like Slack and GitHub, and connect to other services without writing custom tool implementations.

MCP servers can run as local processes (stdio), connect over HTTP/SSE, or run directly within your Elixir application using Hermes MCP modules.

## Quickstart

This example connects to an external MCP server and uses `:allowed_tools` with a wildcard to permit all tools from the server:

```elixir
{:ok, result} = ClaudeCode.query("List all files in the workspace",
  mcp_servers: %{
    "filesystem" => %{
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"]
    }
  },
  allowed_tools: ["mcp__filesystem__*"]
)
```

The agent connects to the filesystem server, discovers its tools, and uses them to list the files.

## Add an MCP server

You can configure MCP servers in three ways: inline with Hermes modules, as command configurations, or from a JSON config file.

### Hermes MCP servers (Elixir)

Pass a [Hermes MCP](https://hexdocs.pm/hermes_mcp) server module atom as the value and the SDK auto-generates the stdio command configuration:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "my-tools" => MyApp.MCPServer
  },
  allowed_tools: ["mcp__my-tools__*"]
)
```

See [Custom Tools](custom-tools.md) for building Hermes MCP servers, passing custom environment variables, and error handling patterns.

### External (stdio) servers

Use any MCP-compatible server via command configuration. This is the standard approach for servers you run on the same machine:

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

### From a config file

Point to a JSON config file with the `:mcp_config` option. The CLI loads this automatically:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_config: "/path/to/mcp-config.json"
)
```

Config file format:

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

The `${GITHUB_TOKEN}` syntax expands environment variables at runtime.

### Mixing Hermes and external servers

The `:mcp_servers` option accepts a mix of Hermes modules and external command configurations:

```elixir
db_url = System.get_env("DATABASE_URL")

{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    # Elixir Hermes module
    "app-tools" => MyApp.MCPServer,
    # External Node.js server
    "browser" => %{command: "npx", args: ["@playwright/mcp@latest"]},
    # Hermes module with custom env
    "db-tools" => %{module: MyApp.DBTools, env: %{"DATABASE_URL" => db_url}}
  },
  allowed_tools: ["mcp__app-tools__*", "mcp__browser__*", "mcp__db-tools__*"]
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
- `:bypass_permissions` -- Skips all safety prompts, including for destructive operations like file deletion or running shell commands. Use with caution, especially in production. Requires `:allow_dangerously_skip_permissions` to be set to `true`.

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  permission_mode: :accept_edits
)
```

See [Permissions](permissions.md) for more details on permission modes.

### Discover available tools

To see what tools an MCP server provides, check the server's documentation or inspect the system init message at the start of each session:

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

MCP servers communicate with your agent using different transport protocols. Check the server's documentation to determine which transport it supports:

- If the docs give you a **command to run** (like `npx @modelcontextprotocol/server-github`), use stdio
- If the docs give you a **URL**, use HTTP or SSE
- If you want to build tools **in Elixir**, use a Hermes MCP server module

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

### Hermes MCP servers

Define custom tools directly in your Elixir application using [Hermes MCP](https://hexdocs.pm/hermes_mcp) modules. The SDK spawns the module as a stdio subprocess automatically. See the [Custom Tools](custom-tools.md) guide for implementation details.

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

## Authentication

Most MCP servers require authentication to access external services. Pass credentials through environment variables or HTTP headers in the server configuration.

### Pass credentials via environment variables

Use the `env` field in the server configuration to pass API keys, tokens, and other credentials:

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
  allowed_tools: ["mcp__github__list_issues"]
)
```

For Hermes MCP modules, pass credentials through the `:env` map in the `%{module: ..., env: ...}` form. See [Custom Tools](custom-tools.md) for details.

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

Before running, create a [GitHub personal access token](https://github.com/settings/tokens) with `repo` scope and set it as an environment variable:

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
  # Verify MCP server connected successfully
  %SystemMessage{tools: tools} ->
    mcp_tools = Enum.filter(tools, &String.starts_with?(&1, "mcp__github__"))
    IO.inspect(mcp_tools, label: "GitHub MCP tools")

  # Log when Claude calls an MCP tool
  %AssistantMessage{message: %{content: blocks}} ->
    for %ToolUseBlock{name: name} <- blocks,
        String.starts_with?(name, "mcp__") do
      IO.puts("MCP tool called: #{name}")
    end

  # Print the final result
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
  # Allow only read queries, not writes
  allowed_tools: ["mcp__postgres__query"]
)
```

## Error handling

MCP servers can fail to connect for various reasons: the server process might not be installed, credentials might be invalid, or a remote server might be unreachable.

The SDK emits a `ClaudeCode.Message.SystemMessage` with subtype `:init` at the start of each query. This message includes connection status for each MCP server. Inspect it to detect connection failures before the agent starts working:

```elixir
session
|> ClaudeCode.stream("Process data")
|> Enum.each(fn
  %ClaudeCode.Message.SystemMessage{subtype: :init} = msg ->
    # Check MCP server connection status in the init message
    IO.inspect(msg, label: "System init")

  %ClaudeCode.Message.ResultMessage{is_error: true, subtype: subtype} ->
    IO.puts("Execution failed: #{subtype}")

  _ ->
    :ok
end)
```

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

The MCP protocol has a default timeout of 60 seconds for server connections. If your server takes longer to start, the connection will fail. For servers that need more startup time, consider:

- Using a lighter-weight server if available
- Pre-warming the server before starting your agent
- Checking server logs for slow initialization causes

## Related resources

- [Custom Tools](custom-tools.md) -- Build Hermes MCP servers with custom Elixir tools
- [Permissions](permissions.md) -- Control which MCP tools your agent can use with `:allowed_tools` and `:disallowed_tools`
- [Subagents](subagents.md) -- Custom agent definitions
- [MCP server directory](https://github.com/modelcontextprotocol/servers) -- Browse available MCP servers for databases, APIs, and more
