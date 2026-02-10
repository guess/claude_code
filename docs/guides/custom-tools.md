# Custom Tools

Build and integrate custom tools to extend Claude's capabilities through MCP servers.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/custom-tools). Examples are adapted for Elixir.

Custom tools allow you to extend Claude Code's capabilities with your own functionality through MCP (Model Context Protocol) servers. In the Elixir SDK, you define tools using [Hermes MCP](https://hex.pm/packages/hermes_mcp) components and connect them to a `ClaudeCode` session via the `:mcp_servers` option. Claude can then invoke your tools during agentic conversations.

## Prerequisites

The `hermes_mcp` dependency is optional. Add it to your `mix.exs` to enable MCP tool integration:

```elixir
defp deps do
  [
    {:claude_code, "~> 0.17"},
    {:hermes_mcp, "~> 0.14"}  # Required for custom tool integration
  ]
end
```

Then run `mix deps.get`.

You can check availability at runtime with `ClaudeCode.MCP.available?/0`.

## Creating custom tools

Define tools as Hermes MCP server components. Each tool is a module that implements `definition/0` and `execute/2`:

```elixir
defmodule MyApp.WeatherTool do
  use Hermes.Server.Component, type: :tool

  @impl true
  def definition do
    %{
      name: "get_weather",
      description: "Get current temperature for a location using coordinates",
      inputSchema: %{
        type: "object",
        properties: %{
          latitude: %{type: "number", description: "Latitude coordinate"},
          longitude: %{type: "number", description: "Longitude coordinate"}
        },
        required: ["latitude", "longitude"]
      }
    }
  end

  @impl true
  def execute(%{"latitude" => lat, "longitude" => lon}, _frame) do
    url = "https://api.open-meteo.com/v1/forecast?latitude=#{lat}&longitude=#{lon}&current=temperature_2m&temperature_unit=fahrenheit"

    case Req.get(url) do
      {:ok, %{body: %{"current" => %{"temperature_2m" => temp}}}} ->
        {:ok, [%{type: "text", text: "Temperature: #{temp}F"}]}

      {:error, reason} ->
        {:error, "Failed to fetch weather: #{inspect(reason)}"}
    end
  end
end
```

Register tools on a Hermes server module:

```elixir
defmodule MyApp.MCPServer do
  use Hermes.Server,
    name: "my-custom-tools",
    version: "1.0.0"

  tool MyApp.WeatherTool
end
```

## Using custom tools

Pass the Hermes server module to a `ClaudeCode` session via the `:mcp_servers` option. The SDK auto-generates the stdio command configuration that the CLI uses to spawn your MCP server as a subprocess:

```elixir
{:ok, result} = ClaudeCode.query("What's the weather in San Francisco?",
  mcp_servers: %{"my-custom-tools" => MyApp.MCPServer}
)
```

Under the hood, the SDK generates this stdio config for the CLI:

```json
{
  "command": "mix",
  "args": ["run", "--no-halt", "-e", "MyApp.MCPServer.start_link(transport: :stdio)"],
  "env": {"MIX_ENV": "prod"}
}
```

### Custom environment variables

Pass custom environment variables to the MCP server subprocess. Your values are merged with `{"MIX_ENV": "prod"}`, with your values taking precedence:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "my-custom-tools" => %{
      module: MyApp.MCPServer,
      env: %{
        "DATABASE_URL" => System.get_env("DATABASE_URL"),
        "DEBUG" => "1"
      }
    }
  }
)
```

### External MCP servers

You can also connect to any MCP-compatible server via raw command configuration:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "playwright" => %{
      command: "npx",
      args: ["@playwright/mcp@latest"]
    }
  }
)
```

### Mixing Hermes and external servers

All three `:mcp_servers` value formats can be combined in a single session:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    # Bare Hermes module
    "app-tools" => MyApp.MCPServer,
    # Hermes module with custom env
    "db-tools" => %{module: MyApp.DBTools, env: %{"DATABASE_URL" => db_url}},
    # External command
    "browser" => %{command: "npx", args: ["@playwright/mcp@latest"]}
  }
)
```

## Tool name format

When MCP tools are exposed to Claude, their names follow a specific naming convention:

```
mcp__<server-name>__<tool-name>
```

For example, a tool named `get_weather` in server `my-custom-tools` becomes:

```
mcp__my-custom-tools__get_weather
```

This naming convention is used when configuring `:allowed_tools`, `:disallowed_tools`, and when observing tool invocations in the stream.

## Configuring allowed tools

Control which MCP tools Claude can use with the `:allowed_tools` and `:disallowed_tools` options:

```elixir
# Allow only specific MCP tools (plus built-in tools)
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-custom-tools" => MyApp.MCPServer},
  allowed_tools: [
    "Read",
    "mcp__my-custom-tools__get_weather"
  ]
)

# Allow all tools from a specific server using wildcard
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-custom-tools" => MyApp.MCPServer},
  allowed_tools: ["mcp__my-custom-tools__*"]
)

# Block specific tools
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-custom-tools" => MyApp.MCPServer},
  disallowed_tools: ["mcp__my-custom-tools__dangerous_tool"]
)
```

### Strict MCP configuration

Use `:strict_mcp_config` to ignore all global MCP configurations and only use the servers you explicitly provide:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"my-custom-tools" => MyApp.MCPServer},
  strict_mcp_config: true
)
```

## Multiple tools example

Register multiple tool components on a single server:

```elixir
defmodule MyApp.CalculatorTool do
  use Hermes.Server.Component, type: :tool

  @impl true
  def definition do
    %{
      name: "calculate",
      description: "Perform mathematical calculations",
      inputSchema: %{
        type: "object",
        properties: %{
          expression: %{type: "string", description: "Mathematical expression to evaluate"},
          precision: %{type: "integer", description: "Decimal precision (default: 2)"}
        },
        required: ["expression"]
      }
    }
  end

  @impl true
  def execute(%{"expression" => expr} = params, _frame) do
    precision = Map.get(params, "precision", 2)

    case safe_eval(expr) do
      {:ok, result} ->
        formatted = :erlang.float_to_binary(result / 1, decimals: precision)
        {:ok, [%{type: "text", text: "#{expr} = #{formatted}"}]}

      {:error, reason} ->
        {:error, "Invalid expression: #{reason}"}
    end
  end

  defp safe_eval(expr) do
    # Use a safe evaluation library in production
    {:ok, Code.eval_string(expr) |> elem(0)}
  rescue
    e -> {:error, Exception.message(e)}
  end
end

defmodule MyApp.TranslateTool do
  use Hermes.Server.Component, type: :tool

  @impl true
  def definition do
    %{
      name: "translate",
      description: "Translate text to a target language",
      inputSchema: %{
        type: "object",
        properties: %{
          text: %{type: "string", description: "Text to translate"},
          target_lang: %{type: "string", description: "Target language code"}
        },
        required: ["text", "target_lang"]
      }
    }
  end

  @impl true
  def execute(%{"text" => text, "target_lang" => lang}, _frame) do
    translated = MyApp.Translator.translate(text, lang)
    {:ok, [%{type: "text", text: translated}]}
  end
end

defmodule MyApp.UtilitiesServer do
  use Hermes.Server,
    name: "utilities",
    version: "1.0.0"

  tool MyApp.CalculatorTool
  tool MyApp.TranslateTool
end
```

Allow only specific tools from the server:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"utilities" => MyApp.UtilitiesServer},
  allowed_tools: [
    "mcp__utilities__calculate",
    "mcp__utilities__translate"
    # "mcp__utilities__search_web" would NOT be allowed
  ]
)
```

## Observing tool invocations

Use `ClaudeCode.Stream.tool_uses/1` to observe when Claude invokes your custom tools:

```elixir
session
|> ClaudeCode.stream("Calculate 5 + 3 and translate 'hello' to Spanish")
|> ClaudeCode.Stream.tool_uses()
|> Enum.each(fn %{name: name, input: input} ->
  IO.puts("Tool called: #{name} with #{inspect(input)}")
end)
```

You can also use the `:tool_callback` option for post-execution monitoring without consuming the stream:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"utilities" => MyApp.UtilitiesServer},
  tool_callback: fn event ->
    Logger.info("Tool #{event.name} executed",
      input: event.input,
      result: event.result,
      is_error: event.is_error
    )
  end
)
```

## Error handling

Handle errors gracefully in your tool `execute/2` callbacks. Return `{:error, message}` to provide meaningful feedback to Claude:

```elixir
defmodule MyApp.APITool do
  use Hermes.Server.Component, type: :tool

  @impl true
  def definition do
    %{
      name: "fetch_data",
      description: "Fetch data from an API endpoint",
      inputSchema: %{
        type: "object",
        properties: %{
          endpoint: %{type: "string", description: "API endpoint URL"}
        },
        required: ["endpoint"]
      }
    }
  end

  @impl true
  def execute(%{"endpoint" => endpoint}, _frame) do
    case Req.get(endpoint) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, [%{type: "text", text: Jason.encode!(body, pretty: true)}]}

      {:ok, %{status: status, body: body}} ->
        {:ok, [%{type: "text", text: "API error #{status}: #{inspect(body)}"}]}

      {:error, reason} ->
        {:error, "Failed to fetch data: #{inspect(reason)}"}
    end
  end
end
```

Claude will see the error message and can adjust its approach or report the issue to the user.

## Example tools

### Database query tool

```elixir
defmodule MyApp.UserQueryTool do
  use Hermes.Server.Component, type: :tool

  import Ecto.Query

  @impl true
  def definition do
    %{
      name: "query_users",
      description: "Search users by name or email",
      inputSchema: %{
        type: "object",
        properties: %{
          search: %{type: "string", description: "Search term for name or email"}
        },
        required: ["search"]
      }
    }
  end

  @impl true
  def execute(%{"search" => search}, _frame) do
    users =
      from(u in MyApp.User,
        where: ilike(u.name, ^"%#{search}%") or ilike(u.email, ^"%#{search}%"),
        limit: 10,
        select: map(u, [:id, :name, :email])
      )
      |> MyApp.Repo.all()

    {:ok, [%{type: "text", text: "Found #{length(users)} users:\n#{Jason.encode!(users, pretty: true)}"}]}
  end
end

defmodule MyApp.DBServer do
  use Hermes.Server,
    name: "database-tools",
    version: "1.0.0"

  tool MyApp.UserQueryTool
end
```

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "database-tools" => %{
      module: MyApp.DBServer,
      env: %{"DATABASE_URL" => System.get_env("DATABASE_URL")}
    }
  },
  system_prompt: "You have access to a user database. Help answer questions about users."
)
```

### API gateway tool

```elixir
defmodule MyApp.APIGatewayTool do
  use Hermes.Server.Component, type: :tool

  @impl true
  def definition do
    %{
      name: "api_request",
      description: "Make authenticated API requests to external services",
      inputSchema: %{
        type: "object",
        properties: %{
          service: %{
            type: "string",
            enum: ["github", "slack"],
            description: "Service to call"
          },
          endpoint: %{type: "string", description: "API endpoint path"},
          method: %{
            type: "string",
            enum: ["GET", "POST", "PUT", "DELETE"],
            description: "HTTP method"
          },
          body: %{type: "object", description: "Request body (optional)"}
        },
        required: ["service", "endpoint", "method"]
      }
    }
  end

  @impl true
  def execute(%{"service" => service, "endpoint" => endpoint, "method" => method} = params, _frame) do
    config = %{
      "github" => %{base_url: "https://api.github.com", key_env: "GITHUB_TOKEN"},
      "slack" => %{base_url: "https://slack.com/api", key_env: "SLACK_TOKEN"}
    }

    case Map.fetch(config, service) do
      {:ok, %{base_url: base_url, key_env: key_env}} ->
        url = base_url <> endpoint
        headers = [{"authorization", "Bearer #{System.get_env(key_env)}"}]
        body = Map.get(params, "body")

        case Req.request(method: String.downcase(method) |> String.to_atom(), url: url, headers: headers, json: body) do
          {:ok, %{body: data}} ->
            {:ok, [%{type: "text", text: Jason.encode!(data, pretty: true)}]}

          {:error, reason} ->
            {:error, "API request failed: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Unknown service: #{service}"}
    end
  end
end
```

## Next steps

- [MCP](mcp.md) - MCP configuration options and file-based config
- [Subagents](subagents.md) - Define specialized agents with tool access
- [Permissions](permissions.md) - Control tool access and permission modes
- [Streaming Output](streaming-output.md) - Stream tool call progress in real-time
