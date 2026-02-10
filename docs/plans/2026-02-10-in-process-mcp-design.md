# In-Process MCP Servers Design

> Design for running MCP tools in the same BEAM process as the SDK, matching Python/TS SDK `type: "sdk"` support.

## Motivation

The Elixir SDK currently supports MCP servers via two patterns that both spawn separate processes:

1. **Hermes module expansion** -- expands to `mix run --no-halt -e "Module.start_link(transport: :stdio)"`, spawning a whole new BEAM VM
2. **HTTP transport** -- starts a Hermes server on a port via `ClaudeCode.MCP.Server`

Neither allows tools to access the running application's state (Ecto repos, GenServers, caches). The Python and TypeScript SDKs solve this with `type: "sdk"` in-process MCP servers where the SDK routes JSONRPC over the existing control protocol.

**Goals:**

- Tools can access application state in the running BEAM
- Lightweight API -- no boilerplate module-per-tool
- Leverage Hermes for schema conversion and response building
- Use the CLI's existing `type: "sdk"` control protocol support

## Tool Definition API

A `tool` macro inside a `ClaudeCode.Tool.Server` module generates Hermes `Server.Component` modules:

```elixir
defmodule MyApp.Tools do
  use ClaudeCode.Tool.Server, name: "my-tools"

  tool :add, "Add two numbers" do
    field :x, :integer, required: true
    field :y, :integer, required: true

    def execute(%{x: x, y: y}, _frame) do
      {:ok, x + y}
    end
  end

  tool :query_user, "Look up a user by email" do
    field :email, :string, required: true

    def execute(%{email: email}, _frame) do
      case MyApp.Repo.get_by(MyApp.User, email: email) do
        nil -> {:error, "User not found"}
        user -> {:ok, "#{user.name} (#{user.email})"}
      end
    end
  end

  tool :get_time, "Get current UTC time" do
    def execute(_params, _frame) do
      {:ok, DateTime.utc_now() |> to_string()}
    end
  end
end
```

### Schema

Uses Hermes's `field` DSL inside each `tool` block. Hermes handles conversion to JSON Schema. All declared fields are available for `required: true/false` and `default:` options.

### Return Values

Tool handlers return simple values. The macro wraps them into Hermes `Response` format:

| Handler returns | Wrapped to |
|---|---|
| `{:ok, text}` when binary | `{:reply, Response.text(Response.tool(), text), frame}` |
| `{:ok, data}` when map or list | `{:reply, Response.json(Response.tool(), data), frame}` |
| `{:error, message}` | `{:error, message, frame}` |

### Frame Access

Both arities are supported:

```elixir
# No frame needed (most tools)
def execute(%{x: x, y: y}) do
  {:ok, x + y}
end

# When you need session state
def execute(%{query: query}, frame) do
  user = frame.assigns.current_user
  {:ok, "Results for #{user.name}: ..."}
end
```

If the user defines `execute/1`, the macro generates the `execute/2` wrapper with an ignored frame argument.

## Macro Implementation

### `use ClaudeCode.Tool.Server`

Sets up the module:

- Imports the `tool/3` macro
- Registers `@_tools` accumulator attribute
- Stores `@_server_name` from the `:name` option
- Adds `@before_compile` hook to generate `__tool_server__/0`

The `__tool_server__/0` function returns:

```elixir
%{name: "my-tools", tools: [MyApp.Tools.Add, MyApp.Tools.QueryUser, MyApp.Tools.GetTime]}
```

### `tool :name, "description" do ... end`

For each tool block, the macro:

1. **Generates a nested module** (e.g., `MyApp.Tools.Add`) with:
   - `use Hermes.Server.Component, type: :tool`
   - `@moduledoc "Add two numbers"` (the description)
   - `def __tool_name__, do: "add"`
2. **Separates** `field` calls from `def execute` in the block AST
3. **Wraps** field calls inside `schema do ... end`
4. **Renames** user's `execute` to `user_execute` (private)
5. **Generates** a public `execute/2` that calls `user_execute` and wraps the return value
6. **Accumulates** `@_tools {name, module}` on the parent server module

Generated output for `tool :add`:

```elixir
defmodule MyApp.Tools.Add do
  @moduledoc "Add two numbers"
  use Hermes.Server.Component, type: :tool

  def __tool_name__, do: "add"

  schema do
    field :x, :integer, required: true
    field :y, :integer, required: true
  end

  @impl true
  def execute(params, frame) do
    case user_execute(params, frame) do
      {:ok, text} when is_binary(text) ->
        {:reply, Response.text(Response.tool(), text), frame}

      {:ok, data} when is_map(data) or is_list(data) ->
        {:reply, Response.json(Response.tool(), data), frame}

      {:error, message} ->
        {:error, message, frame}
    end
  end

  defp user_execute(%{x: x, y: y}, _frame) do
    {:ok, x + y}
  end
end
```

## Session Integration

### Passing tools to a session

The server module goes into `mcp_servers`:

```elixir
# One-shot
{:ok, result} = ClaudeCode.query("What's 5 + 3?",
  mcp_servers: %{"calc" => MyApp.Tools},
  allowed_tools: ["mcp__calc__add"]
)

# Persistent session
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{"calc" => MyApp.Tools}
)
```

### Detection

`CLI.Command.convert_option/2` checks for the presence of `__tool_server__/0` on the module. If present, it emits `type: "sdk"`. Otherwise, the existing Hermes module expansion to stdio command applies:

```elixir
# Module with __tool_server__/0 → in-process
%{type: "sdk", name: "calc"}

# Hermes.Server module without it → stdio subprocess
%{command: "mix", args: ["run", "--no-halt", "-e", "..."]}
```

### CLI config

The CLI receives:

```
--mcp-config '{"mcpServers":{"calc":{"type":"sdk","name":"calc"}}}'
```

The CLI sees `type: "sdk"` and routes MCP JSONRPC through the control protocol instead of spawning a subprocess.

### Mixed servers

In-process and external servers work together in a single session:

```elixir
ClaudeCode.query("...",
  mcp_servers: %{
    "calc"    => MyApp.Tools,                                     # in-process (sdk)
    "db"      => MyApp.DBServer,                                  # Hermes module (stdio)
    "browser" => %{command: "npx", args: ["@playwright/mcp"]}     # external command
  }
)
```

## Control Protocol Routing

### Message flow

```
CLI stdout
  -> CLI.Parser (parses JSON)
  -> CLI.Control.classify/1 (identifies "mcp_message" subtype)
  -> Adapter.Local forwards to Session
  -> Session routes to MCP.Router
  -> MCP.Router dispatches to tool module
  -> Response sent back via control_response on stdin
```

### Wire format

Inbound (CLI to SDK):

```json
{
  "type": "control_request",
  "request_id": "r1",
  "request": {
    "subtype": "mcp_message",
    "server_name": "calc",
    "message": {
      "jsonrpc": "2.0",
      "id": 1,
      "method": "tools/call",
      "params": {"name": "add", "arguments": {"x": 5, "y": 3}}
    }
  }
}
```

Outbound (SDK to CLI):

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "r1",
    "response": {
      "mcp_response": {
        "jsonrpc": "2.0",
        "id": 1,
        "result": {"content": [{"type": "text", "text": "8"}]}
      }
    }
  }
}
```

### MCP.Router

`ClaudeCode.MCP.Router` dispatches JSONRPC requests to in-process tool server modules:

```elixir
defmodule ClaudeCode.MCP.Router do
  def handle_request(server_module, %{"method" => method} = message) do
    %{tools: tool_modules} = server_module.__tool_server__()

    case method do
      "initialize" ->
        jsonrpc_result(message, %{
          protocolVersion: "2024-11-05",
          capabilities: %{tools: %{}},
          serverInfo: %{name: server_module.__tool_server__().name}
        })

      "tools/list" ->
        tools = Enum.map(tool_modules, &tool_definition/1)
        jsonrpc_result(message, %{tools: tools})

      "tools/call" ->
        %{"params" => %{"name" => name, "arguments" => args}} = message
        call_tool(tool_modules, name, args) |> jsonrpc_result(message)

      "notifications/initialized" ->
        jsonrpc_result(message, %{})

      _ ->
        jsonrpc_error(message, -32601, "Method '#{method}' not supported")
    end
  end
end
```

Tool dispatch calls component `execute/2` directly -- no running Hermes server process:

```elixir
defp call_tool(tool_modules, name, args) do
  case Enum.find(tool_modules, &(&1.__tool_name__() == name)) do
    nil ->
      {:error, -32601, "Tool '#{name}' not found"}

    module ->
      frame = %Hermes.Server.Frame{assigns: %{}}

      try do
        case module.execute(args, frame) do
          {:reply, response, _frame} ->
            %{content: extract_content(response)}

          {:error, message, _frame} ->
            %{content: [%{type: "text", text: message}], is_error: true}
        end
      rescue
        e ->
          %{content: [%{type: "text", text: "Tool error: #{Exception.message(e)}"}],
            is_error: true}
      end
  end
end
```

### Session wiring

The Session holds registered in-process servers and routes control requests:

```elixir
# In Session state, populated at init from mcp_servers option:
%{
  sdk_mcp_servers: %{"calc" => MyApp.Tools}
}

# When a control request arrives:
def handle_control_request(%{subtype: "mcp_message"} = request, state) do
  %{server_name: name, message: jsonrpc} = request
  server_module = state.sdk_mcp_servers[name]
  response = MCP.Router.handle_request(server_module, jsonrpc)
  send_control_response(response, state)
end
```

## Error Handling

**Tool execution errors** are caught and returned as MCP error content (`is_error: true`). Claude sees the error and can adjust its approach.

**JSONRPC-level errors** (unknown server, unknown method, missing tool):

| Error | JSONRPC code | Message |
|---|---|---|
| Unknown server name | -32601 | `"Server 'x' not found"` |
| Unknown JSONRPC method | -32601 | `"Method 'x' not supported"` |
| Tool not found | -32601 | `"Tool 'x' not found"` |
| Tool raises exception | N/A | `is_error: true` with exception message |

## Testing

### Test tool modules directly

Generated modules are standard Hermes components:

```elixir
test "add tool" do
  frame = %Hermes.Server.Frame{assigns: %{}}
  assert {:reply, response, _frame} = MyApp.Tools.Add.execute(%{x: 3, y: 4}, frame)
  assert response_text(response) == "7"
end
```

### Test the Router in isolation

```elixir
test "tools/list returns all registered tools" do
  message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
  response = MCP.Router.handle_request(MyApp.Tools, message)

  assert %{"result" => %{"tools" => tools}} = response
  assert length(tools) == 3
  assert Enum.any?(tools, &(&1["name"] == "add"))
end

test "tools/call dispatches to the right tool" do
  message = %{
    "jsonrpc" => "2.0", "id" => 2,
    "method" => "tools/call",
    "params" => %{"name" => "add", "arguments" => %{"x" => 5, "y" => 3}}
  }

  response = MCP.Router.handle_request(MyApp.Tools, message)
  assert %{"result" => %{"content" => [%{"type" => "text", "text" => "8"}]}} = response
end
```

### Integration with Test adapter

```elixir
test "end-to-end with test adapter" do
  {:ok, session} = ClaudeCode.start_link(
    adapter: ClaudeCode.Adapter.Test,
    mcp_servers: %{"calc" => MyApp.Tools}
  )

  {:ok, result} = ClaudeCode.query(session, "Add 5 and 3")
  assert result.result =~ "8"
end
```

The existing `tool_callback` option continues to work -- the CLI reports MCP tool use/result in the message stream regardless of in-process vs external transport.

## File Structure

### New files

| File | Purpose |
|---|---|
| `lib/claude_code/tool/server.ex` | `ClaudeCode.Tool.Server` -- `use` macro + `tool` block macro |
| `lib/claude_code/mcp/router.ex` | `ClaudeCode.MCP.Router` -- JSONRPC dispatch to in-process tools |
| `test/claude_code/tool/server_test.exs` | Macro expansion, generated module correctness |
| `test/claude_code/mcp/router_test.exs` | JSONRPC routing, tool dispatch, error cases |

### Modified files

| File | Change |
|---|---|
| `lib/claude_code/cli/command.ex` | Detect `__tool_server__/0` -> emit `type: "sdk"` instead of stdio expansion |
| `lib/claude_code/cli/control.ex` | Classify `mcp_message` subtype in control requests |
| `lib/claude_code/session.ex` | Extract `sdk_mcp_servers` at init, route `mcp_message` to Router |
| `lib/claude_code/adapter/local.ex` | Forward `mcp_message` control requests to Session |
| `lib/claude_code/options.ex` | Accept `ClaudeCode.Tool.Server` modules in `:mcp_servers` validation |

## Out of Scope

- **Resources and prompts** -- only tools for now
- **Tool annotations** -- `readOnlyHint`, `destructiveHint`, etc. (easy to add as `tool` macro options later)
- **Running a Hermes server process** -- components are called as plain functions
- **Deprecating existing Hermes expansion** -- `mcp_servers: %{"x" => MyHermesServer}` still works as stdio subprocess
- **Hook system / can_use_tool** -- separate feature
- **Write serialization lock** -- GenServer already serializes queries

## Dependencies

- `hermes_mcp` stays optional -- required only when using in-process tools (they generate `Hermes.Server.Component` modules)
- No new dependencies

## Migration

Existing Hermes module users don't need to change anything. The new `tool` macro is additive:

```elixir
# Before: Hermes module, runs as subprocess
mcp_servers: %{"calc" => MyApp.CalculatorServer}

# After: inline tools, runs in-process
mcp_servers: %{"calc" => MyApp.Tools}
```
