# Custom Tools

Build custom tools for Claude using Hermes MCP servers in Elixir.

## Overview

The ClaudeCode SDK integrates with [Hermes](https://hex.pm/packages/hermes_mcp) MCP servers. You define tools as Elixir modules, and the SDK automatically generates the stdio configuration for the CLI.

## Creating a Hermes MCP Server

```elixir
defmodule MyApp.MCPServer do
  use Hermes.Server,
    name: "my-tools",
    version: "1.0.0"

  tool "search_docs",
    description: "Search project documentation",
    params: %{
      "query" => %{"type" => "string", "description" => "Search query"}
    } do
    results = MyApp.Docs.search(params["query"])
    {:ok, Enum.map_join(results, "\n", & &1.content)}
  end

  tool "get_metrics",
    description: "Get application metrics",
    params: %{
      "metric_name" => %{"type" => "string", "description" => "Metric to retrieve"}
    } do
    case MyApp.Metrics.get(params["metric_name"]) do
      {:ok, value} -> {:ok, "#{params["metric_name"]}: #{value}"}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Connecting to a Session

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "my-tools" => MyApp.MCPServer
  }
)

# Claude can now use search_docs and get_metrics
session
|> ClaudeCode.stream("Search the docs for authentication")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

The SDK generates a stdio config that the CLI uses to spawn your MCP server:

```json
{
  "command": "mix",
  "args": ["run", "--no-halt", "-e", "MyApp.MCPServer.start_link(transport: :stdio)"],
  "env": {"MIX_ENV": "prod"}
}
```

## Custom Environment Variables

Pass custom environment variables to the MCP server process:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "my-tools" => %{
      module: MyApp.MCPServer,
      env: %{
        "DATABASE_URL" => System.get_env("DATABASE_URL"),
        "DEBUG" => "1"
      }
    }
  }
)
```

Custom env vars are merged with `{"MIX_ENV": "prod"}`, with your values taking precedence.

## Integration Example

A complete example with a database-backed tool server:

```elixir
defmodule MyApp.DBTools do
  use Hermes.Server,
    name: "db-tools",
    version: "1.0.0"

  tool "query_users",
    description: "Search users by name or email",
    params: %{
      "search" => %{"type" => "string", "description" => "Search term"}
    } do
    users = MyApp.Repo.all(
      from u in MyApp.User,
      where: ilike(u.name, ^"%#{params["search"]}%")
           or ilike(u.email, ^"%#{params["search"]}%"),
      limit: 10
    )

    {:ok, Jason.encode!(Enum.map(users, &Map.take(&1, [:id, :name, :email])))}
  end
end

# Usage
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"db-tools" => MyApp.DBTools},
  system_prompt: "You have access to a user database. Help answer questions about users."
)
```

## Next Steps

- [MCP](mcp.md) - MCP configuration options
- [Subagents](subagents.md) - Define specialized agents
- [Hooks](hooks.md) - Monitor tool execution
