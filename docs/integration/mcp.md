# MCP Integration

The Model Context Protocol (MCP) lets you expose custom Elixir tools to Claude. This requires the optional `hermes_mcp` dependency.

## Installation

```elixir
# mix.exs
def deps do
  [
    {:claude_code, "~> 0.5.0"},
    {:hermes_mcp, "~> 0.14"}  # Optional MCP support
  ]
end
```

Check if MCP is available:

```elixir
ClaudeCode.MCP.available?()
# => true
```

## Defining Tools

Use Hermes to define tools Claude can invoke:

```elixir
defmodule MyApp.Tools.Calculator do
  use Hermes.Server.Component, type: :tool

  @impl true
  def definition do
    %{
      name: "calculator",
      description: "Perform mathematical calculations",
      inputSchema: %{
        type: "object",
        properties: %{
          operation: %{
            type: "string",
            enum: ["add", "subtract", "multiply", "divide"],
            description: "The operation to perform"
          },
          a: %{type: "number", description: "First operand"},
          b: %{type: "number", description: "Second operand"}
        },
        required: ["operation", "a", "b"]
      }
    }
  end

  @impl true
  def execute(%{"operation" => op, "a" => a, "b" => b}, _frame) do
    result = case op do
      "add" -> a + b
      "subtract" -> a - b
      "multiply" -> a * b
      "divide" when b != 0 -> a / b
      "divide" -> {:error, "Division by zero"}
    end

    case result do
      {:error, msg} -> {:error, msg}
      value -> {:ok, [%{type: "text", text: "Result: #{value}"}]}
    end
  end
end
```

## Database Query Tool

```elixir
defmodule MyApp.Tools.UserSearch do
  use Hermes.Server.Component, type: :tool

  @impl true
  def definition do
    %{
      name: "search_users",
      description: "Search for users in the database",
      inputSchema: %{
        type: "object",
        properties: %{
          email: %{type: "string", description: "Email to search for"},
          limit: %{type: "integer", description: "Max results", default: 10}
        },
        required: ["email"]
      }
    }
  end

  @impl true
  def execute(%{"email" => email} = params, _frame) do
    limit = Map.get(params, "limit", 10)

    users = MyApp.Repo.all(
      from u in MyApp.User,
      where: ilike(u.email, ^"%#{email}%"),
      limit: ^limit,
      select: %{id: u.id, email: u.email, name: u.name}
    )

    {:ok, [%{type: "text", text: Jason.encode!(users, pretty: true)}]}
  end
end
```

## Creating the MCP Server

```elixir
defmodule MyApp.MCPServer do
  use Hermes.Server,
    name: "myapp-tools",
    version: "1.0.0"

  tool MyApp.Tools.Calculator
  tool MyApp.Tools.UserSearch
end
```

## Connecting to ClaudeCode

### Using `mcp_servers` (Recommended)

The simplest way to connect MCP servers is with the `mcp_servers` option. Pass a map where keys are server names and values are either Hermes MCP modules or command configurations:

```elixir
# Connect a Hermes MCP server directly
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "myapp-tools" => MyApp.MCPServer
  }
)

# Claude can now use your tools!
{:ok, response} = ClaudeCode.query(session, "Calculate 15 * 7")
# Claude invokes your calculator tool and returns the result
```

When you pass a module atom, ClaudeCode automatically generates the stdio transport configuration to spawn your Elixir app with the MCP server.

### Module with Custom Environment

If you need to pass custom environment variables to your Hermes MCP server, use a map with a `module` key:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "myapp-tools" => %{
      module: MyApp.MCPServer,
      env: %{"DEBUG" => "1", "LOG_LEVEL" => "debug"}
    }
  }
)
```

Custom env is merged with the defaults (`MIX_ENV: "prod"`). You can override `MIX_ENV` if needed:

```elixir
mcp_servers: %{
  "myapp-tools" => %{module: MyApp.MCPServer, env: %{"MIX_ENV" => "dev"}}
}
```

### Combining Hermes and External MCP Servers

You can mix Hermes modules with external MCP servers (like Playwright, filesystem, etc.):

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    # Your Hermes MCP server (module atom)
    "myapp-tools" => MyApp.MCPServer,

    # External MCP server (command config)
    "playwright" => %{
      command: "npx",
      args: ["@playwright/mcp@latest"]
    },

    # Another external server with environment variables
    "filesystem" => %{
      command: "npx",
      args: ["-y", "@anthropic/mcp-filesystem", "/path/to/allowed/dir"],
      env: %{"NODE_ENV" => "production"}
    }
  }
)
```

### Query-level MCP Configuration

You can also specify or override MCP servers at query time:

```elixir
# Start session with default servers
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"myapp-tools" => MyApp.MCPServer}
)

# Add additional server for specific query
ClaudeCode.query(session, "Test the login page",
  mcp_servers: %{
    "myapp-tools" => MyApp.MCPServer,
    "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}
  }
)
```

## Production Supervision

Add MCP-enabled sessions to your supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    # Start Claude sessions with MCP servers
    {ClaudeCode.Supervisor, [
      [name: :assistant, mcp_servers: %{"tools" => MyApp.MCPServer}]
    ]},

    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Alternative: File-based Configuration

If you prefer to use a configuration file (e.g., for complex setups or sharing configs), use `mcp_config`:

```elixir
# Start MCP server and get config path
{:ok, config_path} = ClaudeCode.MCP.Server.start_link(
  server: MyApp.MCPServer,
  port: 9001
)

# Start ClaudeCode with MCP config file
{:ok, session} = ClaudeCode.start_link(mcp_config: config_path)
```

### Multiple Servers with Config Files

```elixir
alias ClaudeCode.MCP.Config

# Generate configs for multiple servers
calc_config = Config.http_config("calculator", port: 9001)
db_config = Config.http_config("database", port: 9002)

# Merge configs
merged = Config.merge_configs([calc_config, db_config])

# Write to temp file
{:ok, config_path} = Config.write_temp_config(merged)

# Start ClaudeCode with all servers
{:ok, session} = ClaudeCode.start_link(mcp_config: config_path)
```

### Stdio Transport with Config Files

For command-line MCP tools using config files:

```elixir
alias ClaudeCode.MCP.Config

stdio_config = Config.stdio_config("elixir-tools",
  command: "mix",
  args: ["run", "--no-halt", "-e", "MyApp.MCPServer.start_link(transport: :stdio)"],
  env: %{"MIX_ENV" => "prod"}
)

{:ok, path} = Config.write_temp_config(stdio_config)
```

## Next Steps

- [Tool Callbacks](tool-callbacks.md) - Monitor tool usage
- [Hermes MCP Documentation](https://hexdocs.pm/hermes_mcp) - Full Hermes guide
