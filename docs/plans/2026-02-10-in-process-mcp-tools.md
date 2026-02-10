# In-Process MCP Tools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable MCP tools to run in-process on the BEAM, accessing application state directly, using the CLI's `type: "sdk"` control protocol.

**Architecture:** A `tool` macro generates Hermes `Server.Component` modules at compile time. At runtime, `MCP.Router` dispatches JSONRPC requests to these modules. The adapter handles `mcp_message` control requests from the CLI and responds with tool results. `CLI.Command` detects in-process modules and emits `type: "sdk"` config.

**Tech Stack:** Elixir macros, Hermes MCP (optional dep), existing control protocol infrastructure

---

### Task 1: Tool.Server Macro

Generates Hermes `Server.Component` tool modules from a concise DSL. Each `tool` block becomes a nested module with schema, execute, and metadata.

**Files:**
- Create: `test/support/test_tools.ex`
- Create: `test/claude_code/tool/server_test.exs`
- Create: `lib/claude_code/tool/server.ex`

**Step 1: Write the test fixture module**

Create `test/support/test_tools.ex` — this module will be used across all tests:

```elixir
defmodule ClaudeCode.TestTools do
  use ClaudeCode.Tool.Server, name: "test-tools"

  tool :add, "Add two numbers" do
    field :x, :integer, required: true
    field :y, :integer, required: true

    def execute(%{x: x, y: y}) do
      {:ok, "#{x + y}"}
    end
  end

  tool :greet, "Greet a user" do
    field :name, :string, required: true

    def execute(%{name: name}) do
      {:ok, "Hello, #{name}!"}
    end
  end

  tool :get_time, "Get current UTC time" do
    def execute(_params) do
      {:ok, DateTime.utc_now() |> to_string()}
    end
  end

  tool :return_map, "Return structured data" do
    field :key, :string, required: true

    def execute(%{key: key}) do
      {:ok, %{key: key, value: "data"}}
    end
  end

  tool :failing_tool, "Always fails" do
    def execute(_params) do
      {:error, "Something went wrong"}
    end
  end
end
```

**Step 2: Write the failing tests**

Create `test/claude_code/tool/server_test.exs`:

```elixir
defmodule ClaudeCode.Tool.ServerTest do
  use ExUnit.Case, async: true

  describe "__tool_server__/0" do
    test "returns server metadata with name and tool modules" do
      info = ClaudeCode.TestTools.__tool_server__()

      assert info.name == "test-tools"
      assert is_list(info.tools)
      assert length(info.tools) == 5
    end

    test "tool modules are correctly named" do
      %{tools: tools} = ClaudeCode.TestTools.__tool_server__()
      module_names = Enum.map(tools, & &1) |> Enum.sort()

      assert ClaudeCode.TestTools.Add in module_names
      assert ClaudeCode.TestTools.Greet in module_names
      assert ClaudeCode.TestTools.GetTime in module_names
      assert ClaudeCode.TestTools.ReturnMap in module_names
      assert ClaudeCode.TestTools.FailingTool in module_names
    end
  end

  describe "generated tool modules" do
    test "have __tool_name__/0 returning the string name" do
      assert ClaudeCode.TestTools.Add.__tool_name__() == "add"
      assert ClaudeCode.TestTools.Greet.__tool_name__() == "greet"
      assert ClaudeCode.TestTools.GetTime.__tool_name__() == "get_time"
    end

    test "have input_schema/0 returning JSON Schema" do
      schema = ClaudeCode.TestTools.Add.input_schema()

      assert schema["type"] == "object"
      assert schema["properties"]["x"]["type"] == "integer"
      assert schema["properties"]["y"]["type"] == "integer"
      assert "x" in schema["required"]
      assert "y" in schema["required"]
    end

    test "tool with no fields has empty object schema" do
      schema = ClaudeCode.TestTools.GetTime.input_schema()

      assert schema["type"] == "object"
    end

    test "have __description__/0 matching the tool description" do
      assert ClaudeCode.TestTools.Add.__description__() == "Add two numbers"
      assert ClaudeCode.TestTools.Greet.__description__() == "Greet a user"
    end
  end

  describe "execute/2 wrapping" do
    setup do
      %{frame: %Hermes.Server.Frame{assigns: %{}}}
    end

    test "wraps {:ok, binary} into {:reply, text_response, frame}", %{frame: frame} do
      assert {:reply, response, ^frame} =
               ClaudeCode.TestTools.Add.execute(%{x: 3, y: 4}, frame)

      protocol = Hermes.Server.Response.to_protocol(response)
      assert protocol["content"] == [%{"type" => "text", "text" => "7"}]
      assert protocol["isError"] == false
    end

    test "wraps {:ok, map} into {:reply, json_response, frame}", %{frame: frame} do
      assert {:reply, response, ^frame} =
               ClaudeCode.TestTools.ReturnMap.execute(%{key: "test"}, frame)

      protocol = Hermes.Server.Response.to_protocol(response)
      [%{"type" => "text", "text" => json_text}] = protocol["content"]
      decoded = Jason.decode!(json_text)
      assert decoded["key"] == "test"
      assert decoded["value"] == "data"
    end

    test "wraps {:error, message} into {:error, Error, frame}", %{frame: frame} do
      assert {:error, %Hermes.MCP.Error{message: "Something went wrong"}, ^frame} =
               ClaudeCode.TestTools.FailingTool.execute(%{}, frame)
    end

    test "execute/1 tools receive params without frame", %{frame: frame} do
      # GetTime has execute/1 — the macro should generate execute/2 wrapper
      assert {:reply, response, ^frame} =
               ClaudeCode.TestTools.GetTime.execute(%{}, frame)

      protocol = Hermes.Server.Response.to_protocol(response)
      [%{"type" => "text", "text" => time_str}] = protocol["content"]
      assert {:ok, _, _} = DateTime.from_iso8601(time_str)
    end
  end

  describe "sdk_server?/1" do
    test "returns true for Tool.Server modules" do
      assert ClaudeCode.Tool.Server.sdk_server?(ClaudeCode.TestTools)
    end

    test "returns false for regular modules" do
      refute ClaudeCode.Tool.Server.sdk_server?(String)
    end

    test "returns false for non-existent modules" do
      refute ClaudeCode.Tool.Server.sdk_server?(DoesNotExist)
    end
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `mix test test/claude_code/tool/server_test.exs -v`
Expected: Compilation error — `ClaudeCode.Tool.Server` module not found

**Step 4: Write the Tool.Server implementation**

Create `lib/claude_code/tool/server.ex`:

```elixir
defmodule ClaudeCode.Tool.Server do
  @moduledoc """
  Macro for defining in-process MCP tool servers.

  Generates Hermes `Server.Component` tool modules from a concise DSL.
  Each `tool` block becomes a nested module with JSON Schema, execute
  callback, and server metadata.

  ## Usage

      defmodule MyApp.Tools do
        use ClaudeCode.Tool.Server, name: "my-tools"

        tool :add, "Add two numbers" do
          field :x, :integer, required: true
          field :y, :integer, required: true

          def execute(%{x: x, y: y}) do
            {:ok, "\#{x + y}"}
          end
        end

        tool :get_time, "Get current UTC time" do
          def execute(_params) do
            {:ok, DateTime.utc_now() |> to_string()}
          end
        end
      end

  ## Return Values

  Tool handlers return simple values. The macro wraps them:

  | Handler returns               | Wrapped to                              |
  |-------------------------------|----------------------------------------|
  | `{:ok, text}` when binary     | `{:reply, Response.text(...), frame}`   |
  | `{:ok, data}` when map/list   | `{:reply, Response.json(...), frame}`   |
  | `{:error, message}`           | `{:error, Error.execution(msg), frame}` |

  ## Frame Access

  Both arities are supported:

      # No frame needed (most tools)
      def execute(%{x: x, y: y}) do
        {:ok, "\#{x + y}"}
      end

      # When you need session state
      def execute(%{query: query}, frame) do
        user = frame.assigns.current_user
        {:ok, "Results for \#{user.name}"}
      end
  """

  @doc """
  Returns true if the given module is a Tool.Server (has `__tool_server__/0`).
  """
  @spec sdk_server?(module()) :: boolean()
  def sdk_server?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__tool_server__, 0)
  end

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      import ClaudeCode.Tool.Server, only: [tool: 3]
      Module.register_attribute(__MODULE__, :_tools, accumulate: true)
      @_server_name unquote(name)
      @before_compile ClaudeCode.Tool.Server
    end
  end

  defmacro __before_compile__(env) do
    tools = Module.get_attribute(env.module, :_tools) |> Enum.reverse()
    server_name = Module.get_attribute(env.module, :_server_name)

    quote do
      @doc false
      def __tool_server__ do
        %{name: unquote(server_name), tools: unquote(tools)}
      end
    end
  end

  @doc false
  defmacro tool(name, description, do: block) do
    caller_module = __CALLER__.module
    module_suffix = name |> to_string() |> Macro.camelize()
    module_name = Module.concat(caller_module, module_suffix)

    {field_asts, execute_def} = split_tool_block(block)
    schema_block = build_schema_block(field_asts)
    {execute_wrapper, user_execute} = build_execute(execute_def, name)

    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(description)
        use Hermes.Server.Component, type: :tool

        alias Hermes.MCP.Error, as: MCPError
        alias Hermes.Server.Response

        @doc false
        def __tool_name__, do: unquote(to_string(name))

        unquote(schema_block)

        @doc false
        def __wrap_result__({:ok, text}, frame) when is_binary(text) do
          {:reply, Response.text(Response.tool(), text), frame}
        end

        def __wrap_result__({:ok, data}, frame) when is_map(data) or is_list(data) do
          {:reply, Response.json(Response.tool(), data), frame}
        end

        def __wrap_result__({:ok, value}, frame) do
          {:reply, Response.text(Response.tool(), to_string(value)), frame}
        end

        def __wrap_result__({:error, message}, frame) do
          {:error, MCPError.execution(to_string(message)), frame}
        end

        unquote(execute_wrapper)
        unquote(user_execute)
      end

      @_tools unquote(module_name)
    end
  end

  # -- Private: AST manipulation -----------------------------------------------

  defp split_tool_block({:__block__, _, exprs}) do
    {fields, other} = Enum.split_with(exprs, &field_ast?/1)
    execute_def = Enum.find(other, &execute_def?/1)
    {fields, execute_def}
  end

  defp split_tool_block(single) do
    if execute_def?(single) do
      {[], single}
    else
      {[single], nil}
    end
  end

  defp field_ast?({:field, _, _}), do: true
  defp field_ast?({:embeds_one, _, _}), do: true
  defp field_ast?({:embeds_many, _, _}), do: true
  defp field_ast?(_), do: false

  defp execute_def?({:def, _, [{:execute, _, _} | _]}), do: true
  defp execute_def?(_), do: false

  defp build_schema_block([]) do
    # Empty schema — still need to define __mcp_raw_schema__ for input_schema/0
    quote do
      schema do
      end
    end
  end

  defp build_schema_block(fields) do
    schema_body =
      case fields do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    quote do
      schema do
        unquote(schema_body)
      end
    end
  end

  defp build_execute(nil, name) do
    # No execute defined — generate a no-op with a helpful error
    wrapper =
      quote do
        @impl true
        def execute(_params, frame) do
          {:error, MCPError.execution("Tool #{unquote(to_string(name))} has no execute implementation"), frame}
        end
      end

    {wrapper, nil}
  end

  defp build_execute({:def, meta, [{:execute, emeta, [params_ast]}, body]}, _name) do
    # execute/1 — generate execute/2 wrapper and private user_execute/1
    user_execute =
      {:defp, meta, [{:__user_execute__, emeta, [params_ast]}, body]}

    wrapper =
      quote do
        @impl true
        def execute(params, frame) do
          __wrap_result__(__user_execute__(params), frame)
        end
      end

    {wrapper, user_execute}
  end

  defp build_execute({:def, meta, [{:execute, emeta, [params_ast, frame_ast]}, body]}, _name) do
    # execute/2 — generate execute/2 wrapper and private user_execute/2
    user_execute =
      {:defp, meta, [{:__user_execute__, emeta, [params_ast, frame_ast]}, body]}

    wrapper =
      quote do
        @impl true
        def execute(params, frame) do
          __wrap_result__(__user_execute__(params, frame), frame)
        end
      end

    {wrapper, user_execute}
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `mix test test/claude_code/tool/server_test.exs -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add lib/claude_code/tool/server.ex test/claude_code/tool/server_test.exs test/support/test_tools.ex
git commit -m "feat: add ClaudeCode.Tool.Server macro for in-process MCP tools"
```

---

### Task 2: MCP.Router

Dispatches JSONRPC requests (`initialize`, `tools/list`, `tools/call`) to in-process tool server modules.

**Files:**
- Create: `test/claude_code/mcp/router_test.exs`
- Create: `lib/claude_code/mcp/router.ex`

**Step 1: Write the failing tests**

Create `test/claude_code/mcp/router_test.exs`:

```elixir
defmodule ClaudeCode.MCP.RouterTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Router

  describe "handle_request/2 - initialize" do
    test "returns protocol version and server info" do
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert response["result"]["capabilities"]["tools"] == %{}
      assert response["result"]["serverInfo"]["name"] == "test-tools"
    end
  end

  describe "handle_request/2 - notifications/initialized" do
    test "returns empty result" do
      message = %{"jsonrpc" => "2.0", "id" => 2, "method" => "notifications/initialized"}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["result"] == %{}
    end
  end

  describe "handle_request/2 - tools/list" do
    test "returns all registered tools with schemas" do
      message = %{"jsonrpc" => "2.0", "id" => 3, "method" => "tools/list"}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      tools = response["result"]["tools"]
      assert length(tools) == 5

      add_tool = Enum.find(tools, &(&1["name"] == "add"))
      assert add_tool["description"] == "Add two numbers"
      assert add_tool["inputSchema"]["type"] == "object"
      assert add_tool["inputSchema"]["properties"]["x"]["type"] == "integer"
    end
  end

  describe "handle_request/2 - tools/call" do
    test "dispatches to the correct tool and returns result" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{"name" => "add", "arguments" => %{"x" => 5, "y" => 3}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["result"]["content"] == [%{"type" => "text", "text" => "8"}]
      assert response["result"]["isError"] == false
    end

    test "returns JSON content for map results" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "return_map", "arguments" => %{"key" => "hello"}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      [%{"type" => "text", "text" => json}] = response["result"]["content"]
      decoded = Jason.decode!(json)
      assert decoded["key"] == "hello"
      assert decoded["value"] == "data"
    end

    test "returns error content for failing tools" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "tools/call",
        "params" => %{"name" => "failing_tool", "arguments" => %{}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["result"]["isError"] == true
      [%{"type" => "text", "text" => error_text}] = response["result"]["content"]
      assert error_text =~ "Something went wrong"
    end

    test "returns error for unknown tool name" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/call",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "nonexistent"
    end
  end

  describe "handle_request/2 - unknown method" do
    test "returns method not found error" do
      message = %{"jsonrpc" => "2.0", "id" => 8, "method" => "unknown/method"}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "unknown/method"
    end
  end

  describe "handle_request/2 - tool exception handling" do
    test "catches exceptions and returns error content" do
      # Define a tool that raises at runtime
      defmodule RaisingTools do
        use ClaudeCode.Tool.Server, name: "raising"

        tool :boom, "Raises an error" do
          def execute(_params) do
            raise "kaboom"
          end
        end
      end

      message = %{
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "tools/call",
        "params" => %{"name" => "boom", "arguments" => %{}}
      }

      response = Router.handle_request(RaisingTools, message)

      assert response["result"]["isError"] == true
      [%{"type" => "text", "text" => error_text}] = response["result"]["content"]
      assert error_text =~ "kaboom"
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/mcp/router_test.exs -v`
Expected: Compilation error — `ClaudeCode.MCP.Router` module not found

**Step 3: Write the Router implementation**

Create `lib/claude_code/mcp/router.ex`:

```elixir
defmodule ClaudeCode.MCP.Router do
  @moduledoc """
  Dispatches JSONRPC requests to in-process MCP tool server modules.

  Handles the MCP protocol methods (`initialize`, `tools/list`, `tools/call`)
  by routing to the appropriate tool module's `execute/2` callback.

  This module is called by the adapter when it receives an `mcp_message`
  control request from the CLI for a `type: "sdk"` server.
  """

  @doc """
  Handles a JSONRPC request for the given tool server module.

  Returns a JSONRPC response map ready for JSON encoding.
  """
  @spec handle_request(module(), map()) :: map()
  def handle_request(server_module, %{"method" => method} = message) do
    %{tools: tool_modules, name: server_name} = server_module.__tool_server__()

    case method do
      "initialize" ->
        jsonrpc_result(message, %{
          "protocolVersion" => "2024-11-05",
          "capabilities" => %{"tools" => %{}},
          "serverInfo" => %{"name" => server_name}
        })

      "notifications/initialized" ->
        jsonrpc_result(message, %{})

      "tools/list" ->
        tools = Enum.map(tool_modules, &tool_definition/1)
        jsonrpc_result(message, %{"tools" => tools})

      "tools/call" ->
        %{"params" => %{"name" => name, "arguments" => args}} = message
        call_tool(tool_modules, name, args, message)

      _ ->
        jsonrpc_error(message, -32601, "Method '#{method}' not supported")
    end
  end

  defp tool_definition(module) do
    %{
      "name" => module.__tool_name__(),
      "description" => module.__description__(),
      "inputSchema" => module.input_schema()
    }
  end

  defp call_tool(tool_modules, name, args, message) do
    case Enum.find(tool_modules, &(&1.__tool_name__() == name)) do
      nil ->
        jsonrpc_error(message, -32601, "Tool '#{name}' not found")

      module ->
        atom_args = atomize_keys(args)
        frame = Hermes.Server.Frame.new()

        try do
          case module.execute(atom_args, frame) do
            {:reply, response, _frame} ->
              jsonrpc_result(message, Hermes.Server.Response.to_protocol(response))

            {:error, %{message: error_msg}, _frame} ->
              jsonrpc_result(message, %{
                "content" => [%{"type" => "text", "text" => to_string(error_msg)}],
                "isError" => true
              })
          end
        rescue
          e ->
            jsonrpc_result(message, %{
              "content" => [%{"type" => "text", "text" => "Tool error: #{Exception.message(e)}"}],
              "isError" => true
            })
        end
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp jsonrpc_result(%{"id" => id}, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp jsonrpc_error(%{"id" => id}, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/mcp/router_test.exs -v`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/claude_code/mcp/router.ex test/claude_code/mcp/router_test.exs
git commit -m "feat: add MCP.Router for JSONRPC dispatch to in-process tools"
```

---

### Task 3: CLI.Command SDK Detection

Modify `convert_option(:mcp_servers, ...)` to detect modules with `__tool_server__/0` and emit `type: "sdk"` instead of Hermes stdio expansion.

**Files:**
- Modify: `lib/claude_code/cli/command.ex:259-279`
- Add tests: `test/claude_code/cli/command_test.exs`

**Step 1: Write the failing tests**

Add to `test/claude_code/cli/command_test.exs` inside the `describe "to_cli_args/1"` block:

```elixir
test "emits type sdk for Tool.Server modules in mcp_servers" do
  opts = [mcp_servers: %{"calc" => ClaudeCode.TestTools}]

  args = Command.to_cli_args(opts)
  assert "--mcp-config" in args

  mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
  json_value = Enum.at(args, mcp_index + 1)

  decoded = Jason.decode!(json_value)
  assert decoded["mcpServers"]["calc"]["type"] == "sdk"
  assert decoded["mcpServers"]["calc"]["name"] == "calc"
  refute Map.has_key?(decoded["mcpServers"]["calc"], "command")
end

test "mixes sdk and stdio modules in mcp_servers" do
  opts = [
    mcp_servers: %{
      "calc" => ClaudeCode.TestTools,
      "other" => MyApp.MCPServer,
      "ext" => %{command: "npx", args: ["@playwright/mcp"]}
    }
  ]

  args = Command.to_cli_args(opts)
  mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
  json_value = Enum.at(args, mcp_index + 1)

  decoded = Jason.decode!(json_value)

  # SDK module
  assert decoded["mcpServers"]["calc"]["type"] == "sdk"

  # Hermes module (no __tool_server__)
  assert decoded["mcpServers"]["other"]["command"] == "mix"

  # External command
  assert decoded["mcpServers"]["ext"]["command"] == "npx"
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/cli/command_test.exs --only line:XXX -v`
(replace XXX with the line number of the new tests)
Expected: FAIL — `calc` gets Hermes stdio expansion instead of `type: "sdk"`

**Step 3: Modify `convert_option(:mcp_servers, ...)`**

In `lib/claude_code/cli/command.ex`, replace lines 259-279 (the existing `convert_option(:mcp_servers, ...)` function) with:

```elixir
defp convert_option(:mcp_servers, value) when is_map(value) do
  expanded =
    Map.new(value, fn
      {name, module} when is_atom(module) ->
        {name, expand_mcp_module(name, module, %{})}

      {name, %{module: module} = config} when is_atom(module) ->
        {name, expand_mcp_module(name, module, config)}

      {name, %{"module" => module} = config} when is_atom(module) ->
        {name, expand_mcp_module(name, module, config)}

      {name, config} when is_map(config) ->
        {name, config}
    end)

  json_string = Jason.encode!(%{mcpServers: expanded})
  {"--mcp-config", json_string}
end
```

Add a new helper function after `expand_hermes_module`:

```elixir
defp expand_mcp_module(name, module, config) do
  if ClaudeCode.Tool.Server.sdk_server?(module) do
    %{type: "sdk", name: name}
  else
    expand_hermes_module(module, config)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/cli/command_test.exs -v`
Expected: All tests PASS (both new and existing)

**Step 5: Commit**

```bash
git add lib/claude_code/cli/command.ex test/claude_code/cli/command_test.exs
git commit -m "feat: detect Tool.Server modules and emit type sdk in mcp-config"
```

---

### Task 4: Adapter.Local MCP Message Routing

Handle `mcp_message` control requests from the CLI by dispatching to `MCP.Router` and sending the response back.

**Files:**
- Modify: `lib/claude_code/adapter/local.ex:33-46` (struct)
- Modify: `lib/claude_code/adapter/local.ex:92-104` (init)
- Modify: `lib/claude_code/adapter/local.ex:547-574` (handle_inbound_control_request)
- Create: `test/claude_code/adapter/local/mcp_routing_test.exs`

**Step 1: Write the failing test**

Create `test/claude_code/adapter/local/mcp_routing_test.exs`:

```elixir
defmodule ClaudeCode.Adapter.Local.MCPRoutingTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Local

  describe "extract_sdk_mcp_servers/1" do
    test "extracts Tool.Server modules from mcp_servers option" do
      opts = [
        mcp_servers: %{
          "calc" => ClaudeCode.TestTools,
          "ext" => %{command: "npx", args: ["something"]}
        }
      ]

      result = Local.extract_sdk_mcp_servers(opts)
      assert result == %{"calc" => ClaudeCode.TestTools}
    end

    test "returns empty map when no mcp_servers" do
      assert Local.extract_sdk_mcp_servers([]) == %{}
    end

    test "returns empty map when no sdk servers in mcp_servers" do
      opts = [mcp_servers: %{"ext" => %{command: "npx", args: ["something"]}}]
      assert Local.extract_sdk_mcp_servers(opts) == %{}
    end
  end

  describe "handle_mcp_message/3" do
    test "dispatches to MCP.Router for known server" do
      servers = %{"calc" => ClaudeCode.TestTools}
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "add", "arguments" => %{"x" => 2, "y" => 3}}
      }

      response = Local.handle_mcp_message("calc", jsonrpc, servers)
      assert response["result"]["content"] == [%{"type" => "text", "text" => "5"}]
    end

    test "returns error for unknown server name" do
      servers = %{"calc" => ClaudeCode.TestTools}
      jsonrpc = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}

      response = Local.handle_mcp_message("unknown", jsonrpc, servers)
      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "unknown"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/adapter/local/mcp_routing_test.exs -v`
Expected: FAIL — `extract_sdk_mcp_servers/1` and `handle_mcp_message/3` not defined

**Step 3: Modify Adapter.Local**

In `lib/claude_code/adapter/local.ex`:

**3a.** Add `sdk_mcp_servers` to struct (around line 33):

```elixir
defstruct [
  :session,
  :session_options,
  :port,
  :buffer,
  :current_request,
  :api_key,
  :server_info,
  :hook_registry,
  sdk_mcp_servers: %{},
  status: :provisioning,
  control_counter: 0,
  pending_control_requests: %{},
  max_buffer_size: 1_048_576
]
```

**3b.** Add alias for MCP.Router at top of module (after existing aliases):

```elixir
alias ClaudeCode.MCP.Router, as: MCPRouter
```

**3c.** Extract sdk_mcp_servers during init (around line 97, after hook_registry):

```elixir
state = %__MODULE__{
  session: session,
  session_options: opts,
  buffer: "",
  api_key: Keyword.get(opts, :api_key),
  max_buffer_size: Keyword.get(opts, :max_buffer_size, 1_048_576),
  hook_registry: hook_registry,
  sdk_mcp_servers: extract_sdk_mcp_servers(opts)
}
```

**3d.** Add `mcp_message` case to `handle_inbound_control_request` (around line 553):

```elixir
response_data =
  case subtype do
    "can_use_tool" ->
      handle_can_use_tool(request, state)

    "hook_callback" ->
      handle_hook_callback(request, state)

    "mcp_message" ->
      server_name = request["server_name"]
      jsonrpc = request["message"]
      mcp_response = handle_mcp_message(server_name, jsonrpc, state.sdk_mcp_servers)
      %{"mcp_response" => mcp_response}

    _ ->
      Logger.warning("Received unhandled control request: #{subtype}")
      nil
  end
```

**3e.** Add the two public helper functions (after `shell_escape`):

```elixir
@doc false
def extract_sdk_mcp_servers(opts) do
  case Keyword.get(opts, :mcp_servers) do
    nil ->
      %{}

    servers when is_map(servers) ->
      Map.new(
        Enum.filter(servers, fn
          {_name, module} when is_atom(module) ->
            ClaudeCode.Tool.Server.sdk_server?(module)

          _ ->
            false
        end)
      )
  end
end

@doc false
def handle_mcp_message(server_name, jsonrpc, sdk_mcp_servers) do
  case Map.get(sdk_mcp_servers, server_name) do
    nil ->
      %{
        "jsonrpc" => "2.0",
        "id" => jsonrpc["id"],
        "error" => %{"code" => -32601, "message" => "Server '#{server_name}' not found"}
      }

    module ->
      MCPRouter.handle_request(module, jsonrpc)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/local/mcp_routing_test.exs -v`
Expected: All tests PASS

Then run full test suite:

Run: `mix test -v`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/claude_code/adapter/local.ex test/claude_code/adapter/local/mcp_routing_test.exs
git commit -m "feat: route mcp_message control requests to in-process tool servers"
```

---

### Task 5: Quality Checks

**Step 1: Run quality checks**

Run: `mix quality`
Expected: All checks pass (compile, format, credo, dialyzer)

**Step 2: Fix any issues**

If `mix format` flags formatting issues, run `mix format` and recommit.
If `mix credo --strict` flags issues, fix them.
If `mix dialyzer` flags issues, add typespecs or fix type mismatches.

**Step 3: Commit if needed**

```bash
git add -A
git commit -m "chore: fix quality check issues for in-process MCP tools"
```

---

## Implementation Notes

### Key Design Decisions

1. **MCP routing happens in Adapter.Local** (not Session) — follows the existing pattern where `can_use_tool` and `hook_callback` are handled directly in the adapter without forwarding to Session.

2. **`String.to_atom/1` for JSONRPC key atomization** — safe because keys are bounded by the tool's schema definition. The atoms already exist from compile-time `field` declarations.

3. **No Peri validation in Router** — the Hermes schema is used for JSON Schema generation (`tools/list`) but not runtime validation. The user's `execute` function handles its own parameter matching.

4. **`__wrap_result__/2` generated in each tool module** — avoids a shared runtime dependency. Each generated module is self-contained.

### Files Changed Summary

| File | Action |
|------|--------|
| `lib/claude_code/tool/server.ex` | **Create** — Tool.Server macro |
| `lib/claude_code/mcp/router.ex` | **Create** — JSONRPC router |
| `lib/claude_code/cli/command.ex` | **Modify** — SDK detection in `convert_option(:mcp_servers, ...)` |
| `lib/claude_code/adapter/local.ex` | **Modify** — `mcp_message` routing, `sdk_mcp_servers` state |
| `test/support/test_tools.ex` | **Create** — Test fixture |
| `test/claude_code/tool/server_test.exs` | **Create** — Macro tests |
| `test/claude_code/mcp/router_test.exs` | **Create** — Router tests |
| `test/claude_code/cli/command_test.exs` | **Modify** — SDK detection tests |
| `test/claude_code/adapter/local/mcp_routing_test.exs` | **Create** — Adapter routing tests |
