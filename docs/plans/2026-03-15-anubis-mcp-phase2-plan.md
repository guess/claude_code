# AnubisMCP Migration — Phase 2: Add Anubis Backend + Swap Default

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `anubis_mcp` as a dependency, implement `Backend.Anubis`, update the `tool/3` macro to generate Anubis components, centralize backend detection in `ClaudeCode.MCP`, and update docs to drop Hermes branding.

**Architecture:** Create `Backend.Anubis` implementing the same `Backend` behaviour as `Backend.Hermes`. Rewrite the `Server` macro to generate `Anubis.Server.Component.Tool` modules instead of `Hermes.Server.Component` modules. Move backend detection logic from `CLI.Command` into `ClaudeCode.MCP.backend_for/1` so both `Router` and `CLI.Command` use a single detection point. Update docs and deprecate Hermes subprocess path.

**Tech Stack:** Elixir, AnubisMCP (`anubis_mcp`), Hermes MCP (`hermes_mcp`, now optional), ExUnit

---

## Context for the Implementer

### Current State (After Phase 1)

Hermes references are confined to two places:

1. **`lib/claude_code/mcp/backend/hermes.ex`** — Backend implementation using Hermes Frame/Response/Component/Schema
2. **`lib/claude_code/mcp/server.ex`** — Macro generates `Hermes.Server.Component` modules with `schema` blocks, `Hermes.MCP.Error`, `Hermes.Server.Response`

The Router delegates entirely to `Backend.Hermes`. `CLI.Command` uses `HermesBackend.compatible?/1` for subprocess detection.

### AnubisMCP Tool Component API

Anubis tools are modules implementing `Anubis.Server.Component.Tool` behaviour:

```elixir
# Required callbacks:
name/0        :: String.t()        # tool name
description/0 :: String.t()        # tool description
input_schema/0 :: map()            # JSON Schema map
execute/2     :: (params, frame) -> {:ok, result} | {:ok, result, frame} | {:error, reason}
```

Anubis also uses Peri for schema validation (same as Hermes), so param validation patterns are compatible.

### Key Differences from Hermes

| Aspect | Hermes | Anubis |
|--------|--------|--------|
| Component macro | `use Hermes.Server.Component, type: :tool` | `use Anubis.Server.Component, type: :tool` |
| Schema DSL | `schema do field ... end` | Manual `input_schema/0` callback returning JSON Schema map |
| Tool name | `__tool_name__/0` (custom) | `name/0` (standard callback) |
| Description | `__description__/0` via `@moduledoc` | `description/0` (standard callback) |
| Execute return | `{:reply, response, frame}` / `{:error, error, frame}` | `{:ok, result}` / `{:ok, result, frame}` / `{:error, reason}` |
| Response building | `Hermes.Server.Response.text/json` | Return raw values, framework wraps |
| Error building | `Hermes.MCP.Error.execution(msg)` | Return `{:error, reason_string}` |
| Frame | `Hermes.Server.Frame.new(assigns)` | Anubis frame (similar concept) |
| Raw schema | `__mcp_raw_schema__/0` | `input_schema/0` returns JSON Schema directly |
| Validation | `Component.__clean_schema_for_peri__` + `Peri.validate` | Anubis validates internally, or use Peri directly on JSON Schema |

---

### Task 1: Centralize Backend Detection in `ClaudeCode.MCP`

**Files:**
- Modify: `lib/claude_code/mcp.ex`
- Modify: `lib/claude_code/cli/command.ex`
- Modify: `lib/claude_code/mcp/router.ex`
- Test: `test/claude_code/mcp/mcp_test.exs` (new)

**Step 1: Write failing test for `backend_for/1`**

Create `test/claude_code/mcp/mcp_test.exs`:

```elixir
defmodule ClaudeCode.MCPTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP

  describe "backend_for/1" do
    test "returns :sdk for SDK server modules" do
      assert MCP.backend_for(ClaudeCode.TestTools) == :sdk
    end

    test "returns {:subprocess, Backend.Hermes} for Hermes-compatible modules" do
      defmodule FakeHermesServer do
        @moduledoc false
        def start_link(_opts), do: {:ok, self()}
      end

      assert MCP.backend_for(FakeHermesServer) == {:subprocess, ClaudeCode.MCP.Backend.Hermes}
    end

    test "returns :unknown for unrecognized modules" do
      assert MCP.backend_for(String) == :unknown
    end

    test "returns :unknown for non-existent modules" do
      assert MCP.backend_for(DoesNotExist) == :unknown
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/mcp/mcp_test.exs`
Expected: FAIL — `backend_for/1` doesn't exist yet

**Step 3: Implement `backend_for/1` in `ClaudeCode.MCP` and update moduledoc**

Replace the entire `lib/claude_code/mcp.ex` content with:

```elixir
defmodule ClaudeCode.MCP do
  @moduledoc """
  Integration with the Model Context Protocol (MCP).

  This module provides the MCP integration layer. Custom tools are defined
  with `ClaudeCode.MCP.Server` and passed via `:mcp_servers`.

  ## Usage

  Define tools with `ClaudeCode.MCP.Server` and pass them via `:mcp_servers`:

      defmodule MyApp.Tools do
        use ClaudeCode.MCP.Server, name: "my-tools"

        tool :add, "Add two numbers" do
          field :x, :integer, required: true
          field :y, :integer, required: true
          def execute(%{x: x, y: y}), do: {:ok, "\#{x + y}"}
        end
      end

      {:ok, result} = ClaudeCode.query("What is 5 + 3?",
        mcp_servers: %{"my-tools" => MyApp.Tools},
        allowed_tools: ["mcp__my-tools__add"]
      )

  See the [Custom Tools](docs/guides/custom-tools.md) guide for details.
  """

  alias ClaudeCode.MCP.Backend
  alias ClaudeCode.MCP.Server

  @doc """
  Determines which backend handles the given MCP module.

  Returns:
  - `:sdk` — in-process SDK server (handled via Router, no subprocess)
  - `{:subprocess, backend_module}` — subprocess server, with the backend that can expand it
  - `:unknown` — unrecognized module
  """
  @spec backend_for(module()) :: :sdk | {:subprocess, module()} | :unknown
  def backend_for(module) when is_atom(module) do
    cond do
      Server.sdk_server?(module) -> :sdk
      Backend.Hermes.compatible?(module) -> {:subprocess, Backend.Hermes}
      true -> :unknown
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/mcp/mcp_test.exs`
Expected: PASS

**Step 5: Update `CLI.Command` to use `ClaudeCode.MCP.backend_for/1`**

In `lib/claude_code/cli/command.ex`, replace the alias and `expand_mcp_module/3`:

Remove the alias:
```elixir
# REMOVE this line:
alias ClaudeCode.MCP.Backend.Hermes, as: HermesBackend
```

Replace `expand_mcp_module/3` (around line 457) with:

```elixir
defp expand_mcp_module(name, module, config) do
  case ClaudeCode.MCP.backend_for(module) do
    :sdk ->
      %{type: "sdk", name: name}

    {:subprocess, _backend} ->
      expand_subprocess_module(module, config)

    :unknown ->
      raise ArgumentError,
            "Module #{inspect(module)} passed to :mcp_servers is not a recognized MCP server module"
  end
end
```

Rename `expand_hermes_module/2` to `expand_subprocess_module/2` and update the comment:

```elixir
# -- Private: MCP module subprocess expansion ---------------------------------

defp expand_subprocess_module(module, config) do
  # Generate stdio command config for an MCP server module
  # This allows the CLI to spawn the Elixir app with the MCP server
  startup_code = "#{inspect(module)}.start_link(transport: :stdio)"

  # Extract custom env from config (supports both atom and string keys)
  custom_env = config[:env] || config["env"] || %{}
  merged_env = Map.merge(%{"MIX_ENV" => "prod"}, custom_env)

  %{
    command: "mix",
    args: ["run", "--no-halt", "-e", startup_code],
    env: merged_env
  }
end
```

**Step 6: Run tests**

Run: `mix test test/claude_code/cli/command_test.exs test/claude_code/mcp/mcp_test.exs`
Expected: All pass

**Step 7: Run full test suite**

Run: `mix test`
Expected: All pass

**Step 8: Commit**

```
git add lib/claude_code/mcp.ex lib/claude_code/cli/command.ex test/claude_code/mcp/mcp_test.exs
git commit -m "Centralize backend detection in ClaudeCode.MCP.backend_for/1

Move detection logic from CLI.Command into ClaudeCode.MCP so both
Router and Command use a single entry point. Drop Hermes branding
from MCP moduledoc."
```

---

### Task 2: Add `anubis_mcp` Dependency

**Files:**
- Modify: `mix.exs`

**Step 1: Add anubis_mcp and make hermes_mcp optional**

In `mix.exs`, update the deps function. Replace:

```elixir
{:hermes_mcp, "~> 0.14"},
```

With:

```elixir
{:anubis_mcp, "~> 0.4"},
{:hermes_mcp, "~> 0.14", optional: true},
```

**Step 2: Install deps**

Run: `mix deps.get`
Expected: Downloads `anubis_mcp` and its dependencies

**Step 3: Compile**

Run: `mix compile`
Expected: Compiles with no errors

**Step 4: Run full test suite**

Run: `mix test`
Expected: All pass (no behavior change yet)

**Step 5: Commit**

```
git add mix.exs mix.lock
git commit -m "Add anubis_mcp dependency, make hermes_mcp optional"
```

---

### Task 3: Create `Backend.Anubis`

**Files:**
- Create: `lib/claude_code/mcp/backend/anubis.ex`
- Test: `test/claude_code/mcp/backend/anubis_test.exs`

This backend wraps Anubis tool component modules. The key difference from `Backend.Hermes` is how execute results are handled — Anubis tools return `{:ok, result}` directly instead of `{:reply, response, frame}`.

**Step 1: Write failing tests**

Create `test/claude_code/mcp/backend/anubis_test.exs`. Since we haven't updated the macro yet, we need a hand-crafted test server for now. The test server module must implement the same `__tool_server__/0` interface that `ClaudeCode.MCP.Server` generates, but with Anubis-style tool modules underneath.

```elixir
defmodule ClaudeCode.MCP.Backend.AnubisTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Backend.Anubis, as: Backend

  # Hand-crafted Anubis-style tool modules for testing
  # Once the macro is updated (Task 4), these can be replaced with macro-generated modules
  defmodule AnubisAddTool do
    @moduledoc false
    def __tool_name__, do: "add"
    def __description__, do: "Add two numbers"

    def input_schema do
      %{
        "type" => "object",
        "properties" => %{
          "x" => %{"type" => "integer"},
          "y" => %{"type" => "integer"}
        },
        "required" => ["x", "y"]
      }
    end

    def execute(%{x: x, y: y}, _assigns), do: {:ok, "#{x + y}"}
  end

  defmodule AnubisMapTool do
    @moduledoc false
    def __tool_name__, do: "return_map"
    def __description__, do: "Return structured data"

    def input_schema do
      %{
        "type" => "object",
        "properties" => %{"key" => %{"type" => "string"}},
        "required" => ["key"]
      }
    end

    def execute(%{key: key}, _assigns), do: {:ok, %{key: key, value: "data"}}
  end

  defmodule AnubisFailTool do
    @moduledoc false
    def __tool_name__, do: "failing_tool"
    def __description__, do: "Always fails"
    def input_schema, do: %{"type" => "object"}
    def execute(_params, _assigns), do: {:error, "Something went wrong"}
  end

  defmodule AnubisRaiseTool do
    @moduledoc false
    def __tool_name__, do: "raise_tool"
    def __description__, do: "Raises"
    def input_schema, do: %{"type" => "object"}
    def execute(_params, _assigns), do: raise("kaboom")
  end

  defmodule AnubisTestServer do
    @moduledoc false
    def __tool_server__ do
      %{name: "anubis-test", tools: [AnubisAddTool, AnubisMapTool, AnubisFailTool, AnubisRaiseTool]}
    end
  end

  describe "list_tools/1" do
    test "returns tool definitions" do
      tools = Backend.list_tools(AnubisTestServer)
      assert length(tools) == 4

      add = Enum.find(tools, &(&1["name"] == "add"))
      assert add["description"] == "Add two numbers"
      assert add["inputSchema"]["type"] == "object"
    end
  end

  describe "server_info/1" do
    test "returns server name and version" do
      info = Backend.server_info(AnubisTestServer)
      assert info["name"] == "anubis-test"
      assert info["version"] == "1.0.0"
    end
  end

  describe "call_tool/4" do
    test "text result" do
      assert {:ok, result} = Backend.call_tool(AnubisTestServer, "add", %{"x" => 5, "y" => 3}, %{})
      assert result["content"] == [%{"type" => "text", "text" => "8"}]
      assert result["isError"] == false
    end

    test "JSON result for maps" do
      assert {:ok, result} = Backend.call_tool(AnubisTestServer, "return_map", %{"key" => "hello"}, %{})
      [%{"type" => "text", "text" => json}] = result["content"]
      decoded = Jason.decode!(json)
      assert decoded["key"] == "hello"
    end

    test "error result" do
      assert {:ok, result} = Backend.call_tool(AnubisTestServer, "failing_tool", %{}, %{})
      assert result["isError"] == true
      [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "Something went wrong"
    end

    test "unknown tool" do
      assert {:error, msg} = Backend.call_tool(AnubisTestServer, "nonexistent", %{}, %{})
      assert msg =~ "nonexistent"
    end

    test "exception handling" do
      assert {:ok, result} = Backend.call_tool(AnubisTestServer, "raise_tool", %{}, %{})
      assert result["isError"] == true
      [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "kaboom"
    end

    test "passes assigns to tool" do
      defmodule AssignsTool do
        @moduledoc false
        def __tool_name__, do: "whoami"
        def __description__, do: "Returns user"
        def input_schema, do: %{"type" => "object"}

        def execute(_params, assigns) do
          case assigns do
            %{user: user} -> {:ok, "User: #{user}"}
            _ -> {:error, "No user"}
          end
        end
      end

      defmodule AssignsServer do
        @moduledoc false
        def __tool_server__, do: %{name: "assigns-test", tools: [AssignsTool]}
      end

      assert {:ok, result} = Backend.call_tool(AssignsServer, "whoami", %{}, %{user: "alice"})
      assert result["content"] == [%{"type" => "text", "text" => "User: alice"}]
    end
  end

  describe "compatible?/1" do
    test "returns false for regular modules" do
      refute Backend.compatible?(String)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/mcp/backend/anubis_test.exs`
Expected: FAIL — module doesn't exist

**Step 3: Implement `Backend.Anubis`**

Create `lib/claude_code/mcp/backend/anubis.ex`:

```elixir
defmodule ClaudeCode.MCP.Backend.Anubis do
  @moduledoc false
  @behaviour ClaudeCode.MCP.Backend

  alias ClaudeCode.MCP.Server, as: MCPServer

  @impl true
  def list_tools(server_module) do
    %{tools: tool_modules} = server_module.__tool_server__()

    Enum.map(tool_modules, fn module ->
      %{
        "name" => module.__tool_name__(),
        "description" => module.__description__(),
        "inputSchema" => module.input_schema()
      }
    end)
  end

  @impl true
  def call_tool(server_module, tool_name, params, assigns) do
    %{tools: tool_modules} = server_module.__tool_server__()

    case Enum.find(tool_modules, &(&1.__tool_name__() == tool_name)) do
      nil ->
        {:error, "Tool '#{tool_name}' not found"}

      module ->
        atom_params = ClaudeCode.MapUtils.safe_atomize_keys(params)
        execute_tool(module, atom_params, assigns)
    end
  end

  @impl true
  def server_info(server_module) do
    %{name: name} = server_module.__tool_server__()
    %{"name" => name, "version" => "1.0.0"}
  end

  @impl true
  def compatible?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :start_link, 1) and
      not MCPServer.sdk_server?(module)
  end

  # -- Private -----------------------------------------------------------------

  defp execute_tool(module, params, assigns) do
    try do
      case module.execute(params, assigns) do
        {:ok, value} when is_binary(value) ->
          {:ok, %{"content" => [%{"type" => "text", "text" => value}], "isError" => false}}

        {:ok, value} when is_map(value) or is_list(value) ->
          {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(value)}], "isError" => false}}

        {:ok, value} ->
          {:ok, %{"content" => [%{"type" => "text", "text" => to_string(value)}], "isError" => false}}

        {:error, message} when is_binary(message) ->
          {:ok, %{"content" => [%{"type" => "text", "text" => message}], "isError" => true}}

        {:error, message} ->
          {:ok, %{"content" => [%{"type" => "text", "text" => to_string(message)}], "isError" => true}}
      end
    rescue
      e ->
        {:ok,
         %{
           "content" => [%{"type" => "text", "text" => "Tool error: #{Exception.message(e)}"}],
           "isError" => true
         }}
    end
  end
end
```

Note: The Anubis backend calls `module.execute(params, assigns)` directly with the raw assigns map, rather than wrapping in a Hermes Frame. The tool macro (updated in Task 4) will generate `execute/2` that accepts `(params, assigns)`.

**Step 4: Run tests**

Run: `mix test test/claude_code/mcp/backend/anubis_test.exs`
Expected: All pass

**Step 5: Commit**

```
git add lib/claude_code/mcp/backend/anubis.ex test/claude_code/mcp/backend/anubis_test.exs
git commit -m "Add Backend.Anubis implementation"
```

---

### Task 4: Update the `tool/3` Macro to Generate Anubis-Compatible Modules

**Files:**
- Modify: `lib/claude_code/mcp/server.ex`
- Modify: `test/claude_code/mcp/server_test.exs`

This is the biggest change. The macro currently generates `Hermes.Server.Component` modules. After this change, it generates standalone modules with the same interface that `Backend.Anubis` expects.

The generated modules will have:
- `__tool_name__/0` — tool name string (unchanged)
- `__description__/0` — description string (was via `@moduledoc`, now explicit)
- `input_schema/0` — returns JSON Schema map (built from `field` declarations, but no longer uses Hermes `schema` block)
- `execute/2` — `(params, assigns)` instead of `(params, hermes_frame)`, returns `{:ok, value}` / `{:error, msg}` directly

**Step 1: Rewrite the `Server` module**

Replace the entire `lib/claude_code/mcp/server.ex` with:

```elixir
defmodule ClaudeCode.MCP.Server do
  @moduledoc """
  Macro for generating MCP tool modules from a concise DSL.

  Each `tool` block becomes a nested module with schema definitions,
  execute wrappers, and metadata.

  ## Usage

      defmodule MyApp.Tools do
        use ClaudeCode.MCP.Server, name: "my-tools"

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

  ## Generated Module Structure

  Each `tool` block generates a nested module (e.g., `MyApp.Tools.Add`) that:

  - Has `__tool_name__/0` returning the string tool name
  - Has `__description__/0` returning the tool description
  - Has `input_schema/0` returning JSON Schema for the tool's parameters
  - Has `execute/2` accepting `(params, assigns)` and returning `{:ok, value}` or `{:error, message}`

  ## Return Value Wrapping

  The user's `execute` function can return:

  - `{:ok, binary}` - returned as text content
  - `{:ok, map | list}` - returned as JSON content
  - `{:ok, other}` - converted to string and returned as text content
  - `{:error, message}` - returned as error content
  """

  @doc """
  Checks if the given module was defined using `ClaudeCode.MCP.Server`.

  Returns `true` if the module exports `__tool_server__/0`, `false` otherwise.
  """
  @spec sdk_server?(module()) :: boolean()
  def sdk_server?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__tool_server__, 0)
  end

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      import ClaudeCode.MCP.Server, only: [tool: 3]

      Module.register_attribute(__MODULE__, :_tools, accumulate: true)
      Module.put_attribute(__MODULE__, :_server_name, unquote(name))

      @before_compile ClaudeCode.MCP.Server
    end
  end

  defmacro __before_compile__(env) do
    tools = env.module |> Module.get_attribute(:_tools) |> Enum.reverse()
    server_name = Module.get_attribute(env.module, :_server_name)

    quote do
      @doc false
      def __tool_server__ do
        %{name: unquote(server_name), tools: unquote(tools)}
      end
    end
  end

  @doc """
  Defines a tool within a `ClaudeCode.MCP.Server` module.

  ## Parameters

  - `name` - atom name for the tool (e.g., `:add`)
  - `description` - string description of what the tool does
  - `block` - the tool body containing optional `field` declarations and a `def execute` function

  ## Examples

      tool :add, "Add two numbers" do
        field :x, :integer, required: true
        field :y, :integer, required: true

        def execute(%{x: x, y: y}) do
          {:ok, "\#{x + y}"}
        end
      end
  """
  defmacro tool(name, description, do: block) do
    module_name = name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
    tool_name_str = Atom.to_string(name)

    {field_asts, execute_ast} = split_tool_block(block)
    schema_def = build_input_schema(field_asts)
    {execute_wrapper, user_execute_def} = build_execute(execute_ast)

    quote do
      defmodule Module.concat(__MODULE__, unquote(module_name)) do
        @moduledoc false

        import ClaudeCode.MCP.Server, only: [field: 2, field: 3]

        @doc false
        def __tool_name__, do: unquote(tool_name_str)

        @doc false
        def __description__, do: unquote(description)

        unquote(schema_def)

        unquote(user_execute_def)

        unquote(execute_wrapper)
      end

      @_tools Module.concat(__MODULE__, unquote(module_name))
    end
  end

  @doc false
  defmacro field(name, type, opts \\ []) do
    quote do
      @_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  # -- Private helpers for AST manipulation --

  # Splits the tool block AST into field declarations and execute def(s).
  defp split_tool_block({:__block__, _, statements}) do
    {fields, executes} =
      Enum.split_with(statements, fn stmt ->
        not execute_def?(stmt)
      end)

    {fields, executes}
  end

  # Single statement block (just a def execute, no fields)
  defp split_tool_block(single) do
    if execute_def?(single) do
      {[], [single]}
    else
      {[single], []}
    end
  end

  # Checks if an AST node is a `def execute(...)` definition
  defp execute_def?({:def, _, [{:execute, _, _} | _]}), do: true
  defp execute_def?(_), do: false

  # Builds the input_schema/0 function from field declarations
  defp build_input_schema([]) do
    quote do
      Module.register_attribute(__MODULE__, :_fields, accumulate: true)

      @doc false
      def input_schema do
        %{"type" => "object", "properties" => %{}, "required" => []}
      end
    end
  end

  defp build_input_schema(field_asts) do
    quote do
      Module.register_attribute(__MODULE__, :_fields, accumulate: true)

      unquote_splicing(field_asts)

      @before_compile {ClaudeCode.MCP.Server, :__before_compile_schema__}
    end
  end

  defmacro __before_compile_schema__(env) do
    fields = env.module |> Module.get_attribute(:_fields) |> Enum.reverse()

    properties =
      for {name, type, _opts} <- fields, into: %{} do
        {Atom.to_string(name), type_to_json_schema(type)}
      end

    required =
      for {name, _type, opts} <- fields,
          Keyword.get(opts, :required, false),
          do: Atom.to_string(name)

    quote do
      @doc false
      def input_schema do
        %{
          "type" => "object",
          "properties" => unquote(Macro.escape(properties)),
          "required" => unquote(required)
        }
      end
    end
  end

  @doc false
  def type_to_json_schema(:string), do: %{"type" => "string"}
  def type_to_json_schema(:integer), do: %{"type" => "integer"}
  def type_to_json_schema(:float), do: %{"type" => "number"}
  def type_to_json_schema(:number), do: %{"type" => "number"}
  def type_to_json_schema(:boolean), do: %{"type" => "boolean"}
  def type_to_json_schema(:map), do: %{"type" => "object"}
  def type_to_json_schema(:list), do: %{"type" => "array"}
  def type_to_json_schema(other), do: %{"type" => to_string(other)}

  # Builds the execute/2 wrapper and the renamed user execute function.
  defp build_execute(execute_defs) do
    # Rename all user `def execute` clauses to `defp __user_execute__`
    user_defs =
      Enum.map(execute_defs, fn {:def, meta, [{:execute, name_meta, args} | body]} ->
        {:defp, meta, [{:__user_execute__, name_meta, args} | body]}
      end)

    # Detect arity from the first clause
    arity = detect_execute_arity(execute_defs)

    wrapper =
      case arity do
        1 ->
          quote do
            @doc false
            def execute(params, _assigns) do
              __user_execute__(params)
            end
          end

        _2 ->
          quote do
            @doc false
            def execute(params, assigns) do
              __user_execute__(params, assigns)
            end
          end
      end

    combined_user_defs =
      case user_defs do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    {wrapper, combined_user_defs}
  end

  defp detect_execute_arity([{:def, _, [{:execute, _, args} | _]} | _]) when is_list(args) do
    length(args)
  end

  defp detect_execute_arity(_), do: 1
end
```

Key changes:
- No more `use Hermes.Server.Component` — standalone modules
- No more Hermes `schema do ... end` block — `field` is now our own macro that registers `@_fields`
- `__before_compile_schema__` converts accumulated fields into JSON Schema via `input_schema/0`
- `execute/2` now takes `(params, assigns)` instead of `(params, hermes_frame)`
- No more `__wrap_result__` — the Backend handles response wrapping
- `type_to_json_schema/1` maps Elixir types to JSON Schema types

**Step 2: Update server tests**

Replace `test/claude_code/mcp/server_test.exs`:

```elixir
defmodule ClaudeCode.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Server
  alias ClaudeCode.TestTools.Add
  alias ClaudeCode.TestTools.FailingTool
  alias ClaudeCode.TestTools.GetTime
  alias ClaudeCode.TestTools.Greet
  alias ClaudeCode.TestTools.ReturnMap

  describe "__tool_server__/0" do
    test "returns server metadata with name and tool modules" do
      info = ClaudeCode.TestTools.__tool_server__()

      assert info.name == "test-tools"
      assert is_list(info.tools)
      assert length(info.tools) == 5
    end

    test "tool modules are correctly named" do
      %{tools: tools} = ClaudeCode.TestTools.__tool_server__()
      module_names = tools |> Enum.map(& &1) |> Enum.sort()

      assert Add in module_names
      assert Greet in module_names
      assert GetTime in module_names
      assert ReturnMap in module_names
      assert FailingTool in module_names
    end
  end

  describe "generated tool modules" do
    test "have __tool_name__/0 returning the string name" do
      assert Add.__tool_name__() == "add"
      assert Greet.__tool_name__() == "greet"
      assert GetTime.__tool_name__() == "get_time"
    end

    test "have input_schema/0 returning JSON Schema" do
      schema = Add.input_schema()

      assert schema["type"] == "object"
      assert schema["properties"]["x"]["type"] == "integer"
      assert schema["properties"]["y"]["type"] == "integer"
      assert "x" in schema["required"]
      assert "y" in schema["required"]
    end

    test "tool with no fields has empty object schema" do
      schema = GetTime.input_schema()

      assert schema["type"] == "object"
    end

    test "have __description__/0 matching the tool description" do
      assert Add.__description__() == "Add two numbers"
      assert Greet.__description__() == "Greet a user"
    end
  end

  describe "execute/2" do
    test "wraps {:ok, binary} for arity-1 execute" do
      assert {:ok, "7"} = Add.execute(%{x: 3, y: 4}, %{})
    end

    test "wraps {:ok, map} for map results" do
      assert {:ok, %{key: "test", value: "data"}} = ReturnMap.execute(%{key: "test"}, %{})
    end

    test "wraps {:error, message} for failing tools" do
      assert {:error, "Something went wrong"} = FailingTool.execute(%{}, %{})
    end

    test "execute/1 tools ignore assigns" do
      assert {:ok, time_str} = GetTime.execute(%{}, %{})
      assert {:ok, _, _} = DateTime.from_iso8601(time_str)
    end
  end

  describe "execute/2 with assigns" do
    defmodule AssignsTools do
      @moduledoc false
      use Server, name: "assigns-test"

      tool :whoami, "Returns user from assigns" do
        def execute(_params, assigns) do
          case assigns do
            %{user: user} -> {:ok, "User: #{user}"}
            _ -> {:error, "No user"}
          end
        end
      end
    end

    test "passes assigns to arity-2 execute" do
      assert {:ok, "User: alice"} = AssignsTools.Whoami.execute(%{}, %{user: "alice"})
    end

    test "empty assigns when not provided" do
      assert {:error, "No user"} = AssignsTools.Whoami.execute(%{}, %{})
    end
  end

  describe "sdk_server?/1" do
    test "returns true for MCP.Server modules" do
      assert Server.sdk_server?(ClaudeCode.TestTools)
    end

    test "returns false for regular modules" do
      refute Server.sdk_server?(String)
    end

    test "returns false for non-existent modules" do
      refute Server.sdk_server?(DoesNotExist)
    end
  end
end
```

**Step 3: Run tests**

Run: `mix test test/claude_code/mcp/server_test.exs`
Expected: All pass

**Step 4: Run full MCP test suite**

Run: `mix test test/claude_code/mcp/`
Expected: All pass

**Step 5: Run full test suite**

Run: `mix test`
Expected: All pass. Some tests that previously used `Hermes.Server.Frame` or `Hermes.Server.Response` directly will need attention — the Backend.Hermes tests may need updating since the macro now generates different modules.

**Step 6: Commit**

```
git add lib/claude_code/mcp/server.ex test/claude_code/mcp/server_test.exs
git commit -m "Rewrite tool/3 macro to generate standalone modules

Remove Hermes.Server.Component dependency from generated tool modules.
Tools now use execute/2 with (params, assigns) instead of Hermes frame.
Schema generation uses our own field macro and type_to_json_schema/1."
```

---

### Task 5: Update Router to Use `Backend.Anubis`

**Files:**
- Modify: `lib/claude_code/mcp/router.ex`

Since the macro now generates Anubis-compatible modules, the Router should use `Backend.Anubis` instead of `Backend.Hermes`.

**Step 1: Update the Router alias**

In `lib/claude_code/mcp/router.ex`, change:

```elixir
alias ClaudeCode.MCP.Backend.Hermes, as: Backend
```

To:

```elixir
alias ClaudeCode.MCP.Backend.Anubis, as: Backend
```

Also update the `@doc` to remove "Hermes frame" reference — change "assigns to set on the Hermes frame" to "assigns passed to tools".

**Step 2: Run Router tests**

Run: `mix test test/claude_code/mcp/router_test.exs`
Expected: All pass

**Step 3: Run full test suite**

Run: `mix test`
Expected: All pass

**Step 4: Commit**

```
git add lib/claude_code/mcp/router.ex
git commit -m "Switch Router from Backend.Hermes to Backend.Anubis"
```

---

### Task 6: Update `ClaudeCode.MCP.backend_for/1` with Anubis Detection

**Files:**
- Modify: `lib/claude_code/mcp.ex`
- Modify: `test/claude_code/mcp/mcp_test.exs`

**Step 1: Add Anubis detection to `backend_for/1`**

In `lib/claude_code/mcp.ex`, update the `backend_for/1` function:

```elixir
def backend_for(module) when is_atom(module) do
  cond do
    Server.sdk_server?(module) -> :sdk
    Backend.Anubis.compatible?(module) -> {:subprocess, Backend.Anubis}
    Backend.Hermes.compatible?(module) -> {:subprocess, Backend.Hermes}
    true -> :unknown
  end
end
```

Add the Anubis alias at the top (it's already aliased via `Backend`).

**Step 2: Update test**

In `test/claude_code/mcp/mcp_test.exs`, update the Hermes test to verify both backends are tried, and add a test noting the current behavior (both backends have the same `compatible?/1` check for now — they both check for `start_link/1`):

```elixir
test "returns {:subprocess, Backend.Anubis} for compatible subprocess modules" do
  defmodule FakeSubprocessServer do
    @moduledoc false
    def start_link(_opts), do: {:ok, self()}
  end

  # Anubis is checked first
  assert MCP.backend_for(FakeSubprocessServer) == {:subprocess, ClaudeCode.MCP.Backend.Anubis}
end
```

Remove or update the old Hermes test accordingly.

**Step 3: Run tests**

Run: `mix test test/claude_code/mcp/mcp_test.exs`
Expected: All pass

**Step 4: Commit**

```
git add lib/claude_code/mcp.ex test/claude_code/mcp/mcp_test.exs
git commit -m "Add Anubis detection to backend_for/1"
```

---

### Task 7: Update Backend.Hermes Tests

**Files:**
- Modify: `test/claude_code/mcp/backend/hermes_test.exs`

The macro no longer generates Hermes components, so `Backend.Hermes` tests that use `ClaudeCode.TestTools` will fail. The Backend.Hermes is now only relevant for raw Hermes.Server modules passed to `:mcp_servers` (subprocess path). Update tests to use hand-crafted Hermes modules or remove tests that overlap with Backend.Anubis.

**Step 1: Decide what to test**

`Backend.Hermes` is now legacy — it only matters for the subprocess detection path (`compatible?/1`). The `list_tools`, `call_tool`, and `server_info` functions are only used if someone explicitly routes through `Backend.Hermes`, which no longer happens for SDK servers.

Simplify the test file to only test `compatible?/1`. The call/list/info tests can be removed since they're covered by `Backend.Anubis` now.

```elixir
defmodule ClaudeCode.MCP.Backend.HermesTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Backend.Hermes, as: Backend

  describe "compatible?/1" do
    test "returns true for modules with start_link/1 that are not SDK servers" do
      defmodule FakeHermesModule do
        @moduledoc false
        def start_link(_opts), do: {:ok, self()}
      end

      assert Backend.compatible?(FakeHermesModule)
    end

    test "returns false for SDK server modules" do
      refute Backend.compatible?(ClaudeCode.TestTools)
    end

    test "returns false for regular modules" do
      refute Backend.compatible?(String)
    end

    test "returns false for non-existent modules" do
      refute Backend.compatible?(DoesNotExist)
    end
  end
end
```

**Step 2: Run tests**

Run: `mix test test/claude_code/mcp/backend/hermes_test.exs`
Expected: All pass

**Step 3: Commit**

```
git add test/claude_code/mcp/backend/hermes_test.exs
git commit -m "Simplify Backend.Hermes tests to compatible?/1 only"
```

---

### Task 8: Update Documentation

**Files:**
- Modify: `docs/guides/mcp.md`
- Modify: `docs/guides/custom-tools.md`

**Step 1: Update `docs/guides/mcp.md`**

In the "In-process and Hermes MCP servers" section (line 180-201), update to reflect the new architecture:

Replace:
```markdown
### In-process and Hermes MCP servers

The Elixir SDK supports two additional transport types for tools defined in your application code:

- **In-process tools** (`ClaudeCode.MCP.Server`) -- Run inside your BEAM VM with full access to Ecto repos, GenServers, and caches. The SDK routes messages through the control protocol, no subprocess needed.
- **Hermes MCP modules** (`Hermes.Server`) -- Run as a stdio subprocess spawned automatically by the SDK. Use this for full [Hermes MCP](https://hexdocs.pm/hermes_mcp) servers with resources and prompts.
```

With:
```markdown
### In-process MCP servers

The Elixir SDK supports in-process tools defined with `ClaudeCode.MCP.Server`. These run inside your BEAM VM with full access to Ecto repos, GenServers, and caches. The SDK routes messages through the control protocol — no subprocess needed.

For full MCP servers with resources and prompts, pass any module with `start_link/1` (e.g., an [AnubisMCP](https://hexdocs.pm/anubis_mcp) or Hermes server). The SDK auto-detects and spawns it as a stdio subprocess.
```

Update the example block after it (remove the separate "Hermes MCP module" comment):

```elixir
# In-process tool (runs in your BEAM VM)
{:ok, result} = ClaudeCode.query("Find user alice@example.com",
  mcp_servers: %{"my-tools" => MyApp.Tools},
  allowed_tools: ["mcp__my-tools__*"]
)

# External MCP module (spawns as subprocess)
{:ok, result} = ClaudeCode.query("Get the weather",
  mcp_servers: %{"weather" => MyApp.MCPServer},
  allowed_tools: ["mcp__weather__*"]
)
```

In the "Mixing server types" section, update the comment from "Hermes module" to "MCP module":

```elixir
# MCP module (spawns as subprocess)
"db-tools" => %{module: MyApp.DBServer, env: %{"DATABASE_URL" => db_url}},
```

In the transport types bullet list (line 138), update:
```markdown
- If you're building your own tools **in Elixir**, use an [SDK MCP server](#in-process-mcp-servers) (see the [Custom tools](custom-tools.md) guide for details)
```

**Step 2: Update `docs/guides/custom-tools.md`**

This guide has extensive Hermes references. Key updates:

1. Opening paragraph (line 7-11): Remove "Hermes MCP servers" as a separate approach. Replace with:
```markdown
Custom tools allow you to extend Claude Code's capabilities with your own functionality through in-process MCP servers, enabling Claude to interact with external services, APIs, or perform specialized operations. Define tools with `ClaudeCode.MCP.Server` that run in your BEAM VM, with full access to application state (Ecto repos, GenServers, caches).

For connecting to external MCP servers, configuring permissions, and authentication, see the [MCP](mcp.md) guide.
```

2. "How it works" section (line 43-47): Remove all Hermes references:
```markdown
#### How it works

The `tool` macro generates modules with a `input_schema/0` function (JSON Schema) and an `execute/2` callback — all derived from the `field` declarations and your `execute` function. You write `execute/1` (params only) and the macro wraps it automatically. Write `execute/2` if you need access to session-specific context via assigns (see [Passing session context with assigns](#passing-session-context-with-assigns)).

When passed to a session via `:mcp_servers`, the SDK detects in-process tool servers and emits `type: "sdk"` in the MCP configuration. The CLI routes JSONRPC messages through the control protocol instead of spawning a subprocess, and the SDK dispatches them to your tool modules via `ClaudeCode.MCP.Router`.
```

3. "Schema definition" section (line 49-63): Remove "Hermes `field` DSL" reference:
```markdown
#### Schema definition

Use `field` declarations inside each `tool` block. Fields are converted to JSON Schema automatically:
```

4. "Passing session context with assigns" section (line 104-148): Replace "Hermes frame" references with "assigns":
   - Line 106: "Assigns are set on the Hermes frame and available via `execute/2`" → "Assigns are passed to `execute/2` as the second argument"

5. "Hermes MCP servers" section (line 150-210): Replace entirely with a deprecation note or remove. Replace with:
```markdown
### Subprocess MCP servers

For full MCP servers with resources and prompts (beyond in-process tools), pass any module that implements `start_link/1`. The SDK auto-detects it and spawns it as a stdio subprocess:

```elixir
defmodule MyApp.MCPServer do
  use Anubis.Server,
    name: "my-custom-tools",
    version: "1.0.0",
    capabilities: [:tools]

  component MyApp.WeatherTool
end
```

Pass to `:mcp_servers` with optional environment variables:

```elixir
{:ok, session} = ClaudeCode.start_link(
  mcp_servers: %{
    "weather" => %{
      module: MyApp.MCPServer,
      env: %{"API_KEY" => System.get_env("WEATHER_API_KEY")}
    }
  }
)
```
```

6. "Testing" section (line 334-369): Remove Hermes references:
```markdown
### Test in-process tool modules directly

Generated tool modules can be tested without a running session:

```elixir
test "get_weather tool returns temperature" do
  assert {:ok, text} = MyApp.Tools.GetWeather.execute(%{latitude: 37.7, longitude: -122.4}, %{})
  assert text =~ "Temperature"
end
```
```

7. "Error Handling > Hermes MCP tools" section (line 309-328): Replace with Anubis example or remove entirely since in-process tools cover the pattern.

**Step 3: Run `mix docs` to verify docs compile**

Run: `mix docs 2>&1 | grep -i "warning\|error" | head -20`
Expected: No warnings about missing modules

**Step 4: Commit**

```
git add docs/guides/mcp.md docs/guides/custom-tools.md
git commit -m "Update docs: replace Hermes references with backend-agnostic language"
```

---

### Task 9: Quality Checks and Final Verification

**Step 1: Run full test suite**

Run: `mix test`
Expected: All pass

**Step 2: Run quality checks**

Run: `mix quality`
Expected: All pass (compile, format, credo, dialyzer)

**Step 3: Verify Hermes confinement**

Run: `grep -rn "Hermes\." lib/claude_code/mcp/`

Expected output — Hermes should only appear in `backend/hermes.ex`:
```
lib/claude_code/mcp/backend/hermes.ex:6:  alias Hermes.Server.Component
lib/claude_code/mcp/backend/hermes.ex:7:  alias Hermes.Server.Component.Schema
lib/claude_code/mcp/backend/hermes.ex:8:  alias Hermes.Server.Frame
lib/claude_code/mcp/backend/hermes.ex:9:  alias Hermes.Server.Response
```

No Hermes references should remain in `server.ex`, `router.ex`, or `mcp.ex`.

**Step 4: Verify no Hermes in tests (except backend/hermes_test.exs)**

Run: `grep -rn "Hermes\." test/claude_code/mcp/`

Expected: No hits, or only in `backend/hermes_test.exs` if any remain.

**Step 5: Log deprecation notice**

The `Backend.Hermes` module and `hermes_mcp` dependency are now optional and deprecated. Phase 3 will remove them.
