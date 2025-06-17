# Proposal: Elixir MCP Server Integration with ClaudeCode SDK

## Summary

This proposal outlines how the Hermes MCP library can be used to create custom Elixir MCP servers that integrate seamlessly with the ClaudeCode SDK, enabling developers to extend Claude Code's capabilities with custom tools and resources written in Elixir.

## Background

The ClaudeCode SDK currently supports MCP (Model Context Protocol) servers through the `--mcp-config` flag, which allows loading external tools and resources. The Hermes MCP library provides an Elixir implementation of the MCP protocol, making it possible to create MCP servers in Elixir that can be consumed by Claude Code.

## Architecture Overview

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   ClaudeCode SDK    │     │   Claude Code CLI    │     │  Elixir MCP     │
│                     │────▶│                      │────▶│    Server       │
│ session.ex          │     │ --mcp-config         │     │ (Hermes MCP)    │
└─────────────────────┘     └──────────────────────┘     └─────────────────┘
                                       │
                                       ▼
                                ┌─────────────────┐
                                │  MCP Config     │
                                │    JSON         │
                                └─────────────────┘
```

## Implementation Flow

### 1. Creating an Elixir MCP Server

Using Hermes MCP, developers can create custom MCP servers:

```elixir
defmodule MyApp.MCPServer do
  use Hermes.MCP.Server

  @impl true
  def tools do
    [
      %{
        name: "database_query",
        description: "Execute a database query",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "SQL query to execute"},
            database: %{type: "string", description: "Database name"}
          },
          required: ["query"]
        }
      },
      %{
        name: "cache_lookup",
        description: "Look up a value in the cache",
        input_schema: %{
          type: "object",
          properties: %{
            key: %{type: "string", description: "Cache key"}
          },
          required: ["key"]
        }
      }
    ]
  end

  @impl true
  def handle_tool_call("database_query", %{"query" => query} = params) do
    # Execute database query
    {:ok, %{result: "Query results..."}}
  end

  @impl true
  def handle_tool_call("cache_lookup", %{"key" => key}) do
    # Look up in cache
    {:ok, %{value: "Cached value..."}}
  end
end
```

### 2. MCP Server Configuration

The MCP server would be configured in a JSON file:

```json
{
  "mcpServers": {
    "myapp": {
      "command": "mix",
      "args": ["run", "--no-halt", "-e", "MyApp.MCPServer.start()"],
      "env": {
        "MIX_ENV": "prod",
        "DATABASE_URL": "${DATABASE_URL}"
      }
    }
  }
}
```

### 3. Using with ClaudeCode SDK

#### Option A: Direct CLI Usage

```elixir
# Start a session with MCP config
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  mcp_config_path: "mcp-servers.json",
  allowed_tools: ["mcp__myapp__database_query", "mcp__myapp__cache_lookup"]
)

# Query using the MCP tools
{:ok, response} = ClaudeCode.query(session,
  "Look up user_123 in the cache and then query their recent orders"
)
```

#### Option B: Enhanced SDK Integration

Add MCP configuration support directly to the SDK:

```elixir
defmodule ClaudeCode.MCP do
  @moduledoc """
  MCP server configuration and management for ClaudeCode SDK.
  """

  defstruct [:servers, :config_path]

  @doc """
  Creates MCP configuration from Elixir servers.
  """
  def config(servers) when is_list(servers) do
    config = %{
      "mcpServers" =>
        Map.new(servers, fn {name, server_config} ->
          {to_string(name), build_server_config(server_config)}
        end)
    }

    # Write to temporary file
    path = write_temp_config(config)
    %__MODULE__{servers: servers, config_path: path}
  end

  defp build_server_config(%{module: module, env: env}) do
    %{
      "command" => "mix",
      "args" => ["run", "--no-halt", "-e", "#{module}.start()"],
      "env" => env || %{}
    }
  end
end

# Usage
mcp = ClaudeCode.MCP.config([
  myapp: %{
    module: MyApp.MCPServer,
    env: %{"DATABASE_URL" => System.get_env("DATABASE_URL")}
  }
])

{:ok, session} = ClaudeCode.start_link(
  api_key: api_key,
  mcp: mcp,
  allowed_tools: ["mcp__myapp__*"]
)
```

### 4. Permission Handler Integration

Create an Elixir MCP server for handling permissions:

```elixir
defmodule MyApp.PermissionServer do
  use Hermes.MCP.Server

  @impl true
  def tools do
    [%{
      name: "check_permission",
      description: "Check if a tool call is permitted",
      input_schema: %{
        type: "object",
        properties: %{
          tool_name: %{type: "string"},
          input: %{type: "object"}
        },
        required: ["tool_name", "input"]
      }
    }]
  end

  @impl true
  def handle_tool_call("check_permission", %{"tool_name" => tool, "input" => input}) do
    # Custom permission logic
    if permitted?(tool, input) do
      {:ok, %{
        behavior: "allow",
        updatedInput: input
      }}
    else
      {:ok, %{
        behavior: "deny",
        message: "Permission denied for #{tool}"
      }}
    end
  end
end
```

## Benefits

1. **Native Elixir Integration**: Write MCP servers in Elixir using familiar patterns
2. **Type Safety**: Leverage Elixir's pattern matching and specs
3. **OTP Integration**: Use GenServers, Supervisors, and other OTP primitives
4. **Easy Testing**: Test MCP servers using standard ExUnit tests
5. **Performance**: Keep everything in the BEAM VM for efficient communication

## Implementation Steps

### Phase 1: Basic Integration
- [ ] Add `mcp_config_path` option to `ClaudeCode.Options`
- [ ] Update CLI module to handle MCP config flag
- [ ] Create example MCP server using Hermes
- [ ] Document MCP server creation process

### Phase 2: Enhanced Support
- [ ] Add `ClaudeCode.MCP` module for configuration management
- [ ] Support dynamic MCP server registration
- [ ] Add helpers for common MCP patterns
- [ ] Create MCP server testing utilities

### Phase 3: Advanced Features
- [ ] Built-in permission handler MCP server
- [ ] MCP server supervision and lifecycle management
- [ ] Hot code reloading for MCP servers
- [ ] Telemetry integration for MCP tool calls

## Example Use Cases

1. **Database Integration**: Query databases directly from Claude Code
2. **Cache Access**: Read/write to application caches
3. **API Gateways**: Expose internal APIs as MCP tools
4. **Custom Workflows**: Implement domain-specific tools
5. **Permission Management**: Fine-grained control over tool usage

## Testing Strategy

1. **Unit Tests**: Test MCP server handlers in isolation
2. **Integration Tests**: Test full flow with mock CLI
3. **End-to-End Tests**: Test with real Claude Code CLI
4. **Property Tests**: Verify message format compliance

## Security Considerations

1. **Tool Allowlisting**: Require explicit tool permissions
2. **Input Validation**: Validate all MCP tool inputs
3. **Sandboxing**: Run MCP servers in restricted environments
4. **Audit Logging**: Log all MCP tool invocations

## Conclusion

Integrating Hermes MCP with the ClaudeCode SDK provides a powerful way to extend Claude Code's capabilities using Elixir. This approach leverages the strengths of both libraries while maintaining the SDK's clean API and the MCP protocol's flexibility.
