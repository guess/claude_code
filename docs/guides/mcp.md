# MCP (Model Context Protocol)

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/mcp). Examples are adapted for Elixir.

Extend Claude's capabilities with MCP servers that provide custom tools.

## Hermes MCP Servers (Elixir)

The recommended way to add custom tools is with Hermes MCP server modules. The SDK auto-generates the stdio command configuration:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "my-tools" => MyApp.MCPServer
  }
)
```

This generates a CLI config that spawns `mix run --no-halt -e "MyApp.MCPServer.start_link(transport: :stdio)"`.

### With Custom Environment Variables

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "my-tools" => %{module: MyApp.MCPServer, env: %{"DEBUG" => "1"}}
  }
)
```

See [Custom Tools](custom-tools.md) for building Hermes MCP servers.

## External MCP Servers

Use any MCP-compatible server via command configuration:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "playwright" => %{
      command: "npx",
      args: ["@playwright/mcp@latest"]
    },
    "filesystem" => %{
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"]
    }
  }
)
```

## File-Based MCP Configuration

Point to a JSON config file:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_config: "/path/to/mcp-config.json"
)
```

Config file format:

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["server.js"],
      "env": {
        "API_KEY": "..."
      }
    }
  }
}
```

## Mixing Hermes and External Servers

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    # Elixir Hermes module
    "app-tools" => MyApp.MCPServer,
    # External Node.js server
    "browser" => %{command: "npx", args: ["@playwright/mcp@latest"]},
    # Another Hermes module with custom env
    "db-tools" => %{module: MyApp.DBTools, env: %{"DATABASE_URL" => db_url}}
  }
)
```

## Allowing MCP Tools

By default, Claude has access to all tools from configured MCP servers. Use `allowed_tools` to restrict:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  # Only allow specific MCP tools
  allowed_tools: ["Read", "mcp__my-tools__search", "mcp__my-tools__fetch"]
)

# Or allow all tools from a specific server
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  allowed_tools: ["mcp__my-tools__*"]
)
```

MCP tool names follow the pattern `mcp__<server-name>__<tool-name>`.

## Strict MCP Configuration

Ignore global MCP configurations and only use explicitly provided servers:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-tools" => MyApp.MCPServer},
  strict_mcp_config: true
)
```

## Permission Delegation

Delegate permission decisions to an MCP tool:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"permissions" => MyApp.PermissionServer},
  permission_mode: :delegate,
  permission_prompt_tool: "mcp__permissions__check_permission"
)
```

## Next Steps

- [Custom Tools](custom-tools.md) - Build Hermes MCP servers
- [Permissions](permissions.md) - Tool access control
- [Subagents](subagents.md) - Custom agent definitions
