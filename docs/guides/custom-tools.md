# Custom Tools

Build custom tools to extend Claude's capabilities with your own functionality.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/custom-tools). Examples are adapted for Elixir.

> **Partial implementation:** In-process tools via `ClaudeCode.Tool.Server` are not yet implemented. The Hermes MCP subprocess pattern and external command configurations are fully supported today.

Custom tools allow you to extend Claude Code's capabilities through MCP (Model Context Protocol) servers. The Elixir SDK supports two approaches for building tools:

1. **In-process tools** -- Define tools with `ClaudeCode.Tool.Server` that run in your BEAM VM, with full access to application state (Ecto repos, GenServers, caches)
2. **Hermes MCP servers** -- Define tools as [Hermes MCP](https://hex.pm/packages/hermes_mcp) components that run as a separate subprocess

For connecting to external MCP servers, configuring permissions, and authentication, see the [MCP](mcp.md) guide.

## Prerequisites

The `hermes_mcp` dependency is optional. Add it to your `mix.exs` to enable custom tool integration:

```elixir
defp deps do
  [
    {:claude_code, "~> 0.19"},
    {:hermes_mcp, "~> 0.14"}  # Required for custom tool integration
  ]
end
```

Then run `mix deps.get`.

You can check availability at runtime with `ClaudeCode.MCP.available?/0`.

## Creating in-process tools

> **Not yet implemented.** This section describes the planned `ClaudeCode.Tool.Server` API.

Use `ClaudeCode.Tool.Server` to define tools that run in the same BEAM process as your application. This is the recommended approach when your tools need access to application state:

```elixir
defmodule MyApp.Tools do
  use ClaudeCode.Tool.Server, name: "my-tools"

  tool :get_weather, "Get current temperature for a location using coordinates" do
    field :latitude, :float, required: true
    field :longitude, :float, required: true

    def execute(%{latitude: lat, longitude: lon}, _frame) do
      url = "https://api.open-meteo.com/v1/forecast?latitude=#{lat}&longitude=#{lon}&current=temperature_2m&temperature_unit=fahrenheit"

      case Req.get(url) do
        {:ok, %{body: %{"current" => %{"temperature_2m" => temp}}}} ->
          {:ok, "Temperature: #{temp}F"}

        {:error, reason} ->
          {:error, "Failed to fetch weather: #{inspect(reason)}"}
      end
    end
  end
end
```

Pass the module to a session via `:mcp_servers` and it runs in-process automatically:

```elixir
{:ok, result} = ClaudeCode.query("What's the weather in San Francisco?",
  mcp_servers: %{"my-tools" => MyApp.Tools},
  allowed_tools: ["mcp__my-tools__get_weather"]
)
```

### How it works

The `tool` macro generates [Hermes MCP](https://hexdocs.pm/hermes_mcp) `Server.Component` modules under the hood. Each `tool` block becomes a nested module (e.g., `MyApp.Tools.GetWeather`) with a `schema`, `execute/2` callback, and JSON Schema definition -- all derived from the `field` declarations and your `execute` function.

When passed to a session via `:mcp_servers`, the SDK detects in-process tool servers and emits `type: "sdk"` in the MCP configuration. The CLI routes JSONRPC messages through the control protocol instead of spawning a subprocess, and the SDK dispatches them to your tool modules via `ClaudeCode.MCP.Router`.

### Schema definition

Use the Hermes `field` DSL inside each `tool` block. Hermes handles conversion to JSON Schema automatically:

```elixir
tool :search, "Search for items" do
  field :query, :string, required: true
  field :limit, :integer, default: 10
  field :category, :string

  def execute(%{query: query} = params, _frame) do
    limit = Map.get(params, :limit, 10)
    {:ok, "Results for #{query} (limit: #{limit})"}
  end
end
```

### Return values

Tool handlers return simple values. The macro wraps them into the MCP response format automatically:

| Handler returns | Behavior |
|---|---|
| `{:ok, text}` when text is a binary | Returned as text content |
| `{:ok, data}` when data is a map or list | Returned as JSON content |
| `{:error, message}` | Returned as error content (`is_error: true`) |

### Accessing application state

In-process tools can call into your application directly -- Ecto repos, GenServers, caches, and any other running processes. This is the primary advantage over subprocess-based tools:

```elixir
defmodule MyApp.Tools do
  use ClaudeCode.Tool.Server, name: "app-tools"

  tool :query_user, "Look up a user by email" do
    field :email, :string, required: true

    def execute(%{email: email}, _frame) do
      case MyApp.Repo.get_by(MyApp.User, email: email) do
        nil -> {:error, "User not found"}
        user -> {:ok, "#{user.name} (#{user.email})"}
      end
    end
  end

  tool :cache_stats, "Get cache statistics" do
    def execute(_params, _frame) do
      stats = MyApp.Cache.stats()
      {:ok, stats}
    end
  end
end
```

## Creating Hermes MCP tools

For tools that don't need application state access, or when you want a full Hermes MCP server with resources and prompts, define tools as Hermes MCP server components. Each tool is a module that implements `definition/0` and `execute/2`:

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

When passed to `:mcp_servers`, the SDK auto-generates a stdio command configuration that spawns the Hermes server as a subprocess:

```elixir
{:ok, result} = ClaudeCode.query("What's the weather in San Francisco?",
  mcp_servers: %{"my-custom-tools" => MyApp.MCPServer},
  allowed_tools: ["mcp__my-custom-tools__get_weather"]
)
```

## Error handling

Handle errors gracefully in your tool handlers. Return `{:error, message}` to provide meaningful feedback to Claude.

### In-process tools

```elixir
tool :fetch_data, "Fetch data from an API endpoint" do
  field :endpoint, :string, required: true

  def execute(%{endpoint: endpoint}, _frame) do
    case Req.get(endpoint) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "API error: HTTP #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch data: #{inspect(reason)}"}
    end
  end
end
```

### Hermes MCP tools

```elixir
@impl true
def execute(%{"endpoint" => endpoint}, _frame) do
  case Req.get(endpoint) do
    {:ok, %{status: status, body: body}} when status in 200..299 ->
      {:ok, [%{type: "text", text: Jason.encode!(body, pretty: true)}]}

    {:ok, %{status: status}} ->
      {:ok, [%{type: "text", text: "API error: HTTP #{status}"}]}

    {:error, reason} ->
      {:error, "Failed to fetch data: #{inspect(reason)}"}
  end
end
```

Claude sees the error message and can adjust its approach or report the issue to the user. Unhandled exceptions in in-process tools are caught automatically and returned as error content.

For connection-level errors (server failed to start, timeouts), see the [MCP error handling](mcp.md#error-handling) section.

## Testing

### Test in-process tool modules directly

Generated modules are standard Hermes components that can be tested without a running session:

```elixir
test "add tool returns correct result" do
  frame = %Hermes.Server.Frame{assigns: %{}}
  assert {:reply, response, _frame} = MyApp.Tools.Add.execute(%{x: 3, y: 4}, frame)
  # response contains Hermes Response struct with text "7"
end
```

### Test the router in isolation

```elixir
test "tools/list returns all registered tools" do
  message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
  response = ClaudeCode.MCP.Router.handle_request(MyApp.Tools, message)

  assert %{"result" => %{"tools" => tools}} = response
  assert Enum.any?(tools, &(&1["name"] == "get_weather"))
end

test "tools/call dispatches to the right tool" do
  message = %{
    "jsonrpc" => "2.0", "id" => 2,
    "method" => "tools/call",
    "params" => %{"name" => "add", "arguments" => %{"x" => 5, "y" => 3}}
  }

  response = ClaudeCode.MCP.Router.handle_request(MyApp.Tools, message)
  assert %{"result" => %{"content" => [%{"type" => "text", "text" => "8"}]}} = response
end
```

## Example tools

### Database query tool

```elixir
defmodule MyApp.DBTools do
  use ClaudeCode.Tool.Server, name: "database-tools"

  tool :query_users, "Search users by name or email" do
    field :search, :string, required: true

    def execute(%{search: search}, _frame) do
      import Ecto.Query

      users =
        from(u in MyApp.User,
          where: ilike(u.name, ^"%#{search}%") or ilike(u.email, ^"%#{search}%"),
          limit: 10,
          select: map(u, [:id, :name, :email])
        )
        |> MyApp.Repo.all()

      {:ok, %{count: length(users), users: users}}
    end
  end
end
```

### API gateway tool

```elixir
defmodule MyApp.APITools do
  use ClaudeCode.Tool.Server, name: "api-gateway"

  tool :api_request, "Make authenticated API requests to external services" do
    field :service, :string, required: true
    field :endpoint, :string, required: true
    field :method, :string, required: true

    def execute(%{service: service, endpoint: endpoint, method: method}, _frame) do
      config = %{
        "github" => %{base_url: "https://api.github.com", key_env: "GITHUB_TOKEN"},
        "slack" => %{base_url: "https://slack.com/api", key_env: "SLACK_TOKEN"}
      }

      case Map.fetch(config, service) do
        {:ok, %{base_url: base_url, key_env: key_env}} ->
          url = base_url <> endpoint
          headers = [{"authorization", "Bearer #{System.get_env(key_env)}"}]
          http_method = method |> String.downcase() |> String.to_existing_atom()

          case Req.request(method: http_method, url: url, headers: headers) do
            {:ok, %{body: data}} -> {:ok, data}
            {:error, reason} -> {:error, "API request failed: #{inspect(reason)}"}
          end

        :error ->
          {:error, "Unknown service: #{service}. Available: github, slack"}
      end
    end
  end
end
```

### Calculator tool

```elixir
defmodule MyApp.Calculator do
  use ClaudeCode.Tool.Server, name: "calculator"

  tool :calculate, "Perform mathematical calculations" do
    field :expression, :string, required: true
    field :precision, :integer

    def execute(%{expression: expr} = params, _frame) do
      precision = Map.get(params, :precision, 2)

      try do
        {result, _} = Code.eval_string(expr)
        formatted = :erlang.float_to_binary(result / 1, decimals: precision)
        {:ok, "#{expr} = #{formatted}"}
      rescue
        e -> {:error, "Invalid expression: #{Exception.message(e)}"}
      end
    end
  end

  tool :compound_interest, "Calculate compound interest for an investment" do
    field :principal, :float, required: true
    field :rate, :float, required: true
    field :time, :float, required: true
    field :n, :integer

    def execute(%{principal: principal, rate: rate, time: time} = params, _frame) do
      n = Map.get(params, :n, 12)
      amount = principal * :math.pow(1 + rate / n, n * time)
      interest = amount - principal

      {:ok, """
      Investment Analysis:
      Principal: $#{:erlang.float_to_binary(principal, decimals: 2)}
      Rate: #{:erlang.float_to_binary(rate * 100, decimals: 2)}%
      Time: #{time} years
      Compounding: #{n} times per year

      Final Amount: $#{:erlang.float_to_binary(amount, decimals: 2)}
      Interest Earned: $#{:erlang.float_to_binary(interest, decimals: 2)}
      Return: #{:erlang.float_to_binary(interest / principal * 100, decimals: 2)}%\
      """}
    end
  end
end
```

## Next steps

- [MCP](mcp.md) -- Connect to MCP servers, configure permissions, authentication, and troubleshooting
- [Permissions](permissions.md) -- Control tool access and permission modes
- [Streaming Output](streaming-output.md) -- Stream tool call progress in real-time
