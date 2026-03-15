# Custom Tools

Build and integrate custom tools to extend Claude Agent SDK functionality.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/custom-tools). Examples are adapted for Elixir.

Custom tools allow you to extend Claude Code's capabilities with your own functionality through in-process MCP servers, enabling Claude to interact with external services, APIs, or perform specialized operations. Define tools with `ClaudeCode.MCP.Server` that run in your BEAM VM, with full access to application state (Ecto repos, GenServers, caches).

For connecting to external MCP servers, configuring permissions, and authentication, see the [MCP](mcp.md) guide.

## Creating Custom Tools

### In-process tools

Use `ClaudeCode.MCP.Server` to define tools that run in the same BEAM process as your application. This is the recommended approach when your tools need access to application state:

```elixir
defmodule MyApp.Tools do
  use ClaudeCode.MCP.Server, name: "my-tools"

  tool :get_weather, "Get current temperature for a location using coordinates" do
    field :latitude, :float, required: true
    field :longitude, :float, required: true

    def execute(%{latitude: lat, longitude: lon}) do
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

#### How it works

The `tool` macro generates tool modules under the hood. Each `tool` block becomes a nested module (e.g., `MyApp.Tools.GetWeather`) with an `input_schema/0` function (JSON Schema), and an `execute/2` callback -- all derived from the `field` declarations and your `execute` function. You write `execute/1` (params only) and the macro wraps it automatically. Write `execute/2` if you need access to session-specific context via assigns (see [Passing session context with assigns](#passing-session-context-with-assigns)).

When passed to a session via `:mcp_servers`, the SDK detects in-process tool servers and emits `type: "sdk"` in the MCP configuration. The CLI routes JSONRPC messages through the control protocol instead of spawning a subprocess, and the SDK dispatches them to your tool modules via `ClaudeCode.MCP.Router`.

#### Schema definition

Use `field` declarations inside each `tool` block. The SDK handles conversion to JSON Schema automatically:

```elixir
tool :search, "Search for items" do
  field :query, :string, required: true
  field :limit, :integer, default: 10
  field :category, :string

  def execute(%{query: query} = params) do
    limit = Map.get(params, :limit, 10)
    {:ok, "Results for #{query} (limit: #{limit})"}
  end
end
```

#### Return values

Tool handlers return simple values. The macro wraps them into the MCP response format automatically:

| Handler returns | Behavior |
|---|---|
| `{:ok, text}` when text is a binary | Returned as text content |
| `{:ok, data}` when data is a map or list | Returned as JSON content |
| `{:error, message}` | Returned as error content (`is_error: true`) |

#### Accessing application state

In-process tools can call into your application directly -- Ecto repos, GenServers, caches, and any other running processes. This is the primary advantage over subprocess-based tools:

```elixir
defmodule MyApp.Tools do
  use ClaudeCode.MCP.Server, name: "app-tools"

  tool :query_user, "Look up a user by email" do
    field :email, :string, required: true

    def execute(%{email: email}) do
      case MyApp.Repo.get_by(MyApp.User, email: email) do
        nil -> {:error, "User not found"}
        user -> {:ok, "#{user.name} (#{user.email})"}
      end
    end
  end

  tool :cache_stats, "Get cache statistics" do
    def execute(_params) do
      stats = MyApp.Cache.stats()
      {:ok, stats}
    end
  end
end
```

#### Passing session context with assigns

When tools need per-session context (e.g., the current user's scope in a LiveView), pass `:assigns` in the server configuration. Assigns are passed to `execute/2` as the second argument:

```elixir
# LiveView mount -- pass current_scope into the tool's assigns
def mount(_params, _session, socket) do
  scope = socket.assigns.current_scope

  {:ok, session} = ClaudeCode.start_link(
    mcp_servers: %{
      "my-tools" => %{module: MyApp.Tools, assigns: %{scope: scope}}
    },
    allowed_tools: ["mcp__my-tools__*"]
  )

  {:ok, assign(socket, claude_session: session)}
end
```

```elixir
defmodule MyApp.Tools do
  use ClaudeCode.MCP.Server, name: "my-tools"

  tool :my_projects, "List the current user's projects" do
    def execute(_params, frame) do
      scope = frame.assigns.scope
      projects = MyApp.Projects.list_projects(scope)
      {:ok, projects}
    end
  end

  tool :search_docs, "Search documentation" do
    field :query, :string, required: true

    def execute(%{query: query}) do
      # Tools that don't need session context can still use execute/1
      results = MyApp.Docs.search(query)
      {:ok, results}
    end
  end
end
```

Tools that don't need session context continue to use `execute/1`. Mix both forms freely in the same server module.

### Subprocess MCP servers

For full MCP servers with resources and prompts (beyond in-process tools), pass any module that exports `start_link/1`. The SDK auto-detects it and spawns it as a stdio subprocess:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "my-server" => MyApp.MCPServer
  }
)
```

Pass custom environment variables with the `%{module: ..., env: ...}` form:

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

## Using Custom Tools

Pass the custom server to a session via the `:mcp_servers` option. Both in-process and subprocess tools work identically from Claude's perspective.

### Tool Name Format

When MCP tools are exposed to Claude, their names follow a specific format:
- Pattern: `mcp__{server_name}__{tool_name}`
- Example: A tool named `get_weather` in server `"my-tools"` becomes `mcp__my-tools__get_weather`

### Configuring Allowed Tools

You can control which tools Claude can use via the `:allowed_tools` option:

```elixir
# Allow all tools from an in-process server
{:ok, result} = ClaudeCode.query("What's the weather in San Francisco?",
  mcp_servers: %{"my-tools" => MyApp.Tools},
  allowed_tools: ["mcp__my-tools__*"]
)

# Allow specific tools only
{:ok, result} = ClaudeCode.query("Look up alice@example.com",
  mcp_servers: %{"my-tools" => MyApp.Tools},
  allowed_tools: ["mcp__my-tools__query_user"]
)
```

### Multiple Tools Example

When your MCP server has multiple tools, you can selectively allow them:

```elixir
defmodule MyApp.Utilities do
  use ClaudeCode.MCP.Server, name: "utilities"

  tool :calculate, "Perform calculations" do
    field :expression, :string, required: true
    def execute(%{expression: expr}), do: {:ok, "#{Code.eval_string(expr) |> elem(0)}"}
  end

  tool :translate, "Translate text" do
    field :text, :string, required: true
    field :target_lang, :string, required: true
    def execute(%{text: text, target_lang: lang}), do: {:ok, "Translated #{text} to #{lang}"}
  end

  tool :search_web, "Search the web" do
    field :query, :string, required: true
    def execute(%{query: query}), do: {:ok, "Results for: #{query}"}
  end
end

{:ok, result} = ClaudeCode.query(
  "Calculate 5 + 3 and translate 'hello' to Spanish",
  mcp_servers: %{"utilities" => MyApp.Utilities},
  allowed_tools: [
    "mcp__utilities__calculate",   # Allow calculator
    "mcp__utilities__translate"    # Allow translator
    # mcp__utilities__search_web is NOT allowed
  ]
)
```

For details on `:allowed_tools`, wildcards, and alternative permission modes, see [MCP > Allow MCP tools](mcp.md#allow-mcp-tools).

## Error Handling

Handle errors gracefully to provide meaningful feedback to Claude. Return `{:error, message}` from your tool handlers.

### In-process tools

```elixir
tool :fetch_data, "Fetch data from an API endpoint" do
  field :endpoint, :string, required: true

  def execute(%{endpoint: endpoint}) do
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

Claude sees the error message and can adjust its approach or report the issue to the user. Unhandled exceptions in in-process tools are caught automatically and returned as error content.

For connection-level errors (server failed to start, timeouts), see the [MCP error handling](mcp.md#error-handling) section.

## Testing

### Test in-process tool modules directly

Generated tool modules can be tested without a running session:

```elixir
test "get_weather tool returns temperature" do
  assert {:ok, text} = MyApp.Tools.GetWeather.execute(%{latitude: 37.7, longitude: -122.4}, %{})
  assert text =~ "Temperature"
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
    "params" => %{"name" => "get_weather", "arguments" => %{"latitude" => 37.7, "longitude" => -122.4}}
  }

  response = ClaudeCode.MCP.Router.handle_request(MyApp.Tools, message)
  assert %{"result" => %{"content" => [%{"type" => "text", "text" => text}]}} = response
  assert text =~ "Temperature"
end
```

## Example Tools

### Database Query Tool

```elixir
defmodule MyApp.DBTools do
  use ClaudeCode.MCP.Server, name: "database-tools"

  tool :query_users, "Search users by name or email" do
    field :search, :string, required: true

    def execute(%{search: search}) do
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

### API Gateway Tool

```elixir
defmodule MyApp.APITools do
  use ClaudeCode.MCP.Server, name: "api-gateway"

  tool :api_request, "Make authenticated API requests to external services" do
    field :service, :string, required: true
    field :endpoint, :string, required: true
    field :method, :string, required: true

    def execute(%{service: service, endpoint: endpoint, method: method}) do
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

### Calculator Tool

```elixir
defmodule MyApp.Calculator do
  use ClaudeCode.MCP.Server, name: "calculator"

  tool :calculate, "Perform mathematical calculations" do
    field :expression, :string, required: true
    field :precision, :integer

    def execute(%{expression: expr} = params) do
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

    def execute(%{principal: principal, rate: rate, time: time} = params) do
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

## Related Documentation

- [MCP](mcp.md) -- Connect to MCP servers, configure permissions, authentication, and troubleshooting
- [MCP Protocol](https://modelcontextprotocol.io) -- Model Context Protocol specification and resources
- [Permissions](permissions.md) -- Control tool access and permission modes
- [Streaming Output](streaming-output.md) -- Stream tool call progress in real-time
