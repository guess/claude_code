defmodule ClaudeCode.Tool.Server do
  @moduledoc """
  Macro for generating Hermes MCP tool modules from a concise DSL.

  Each `tool` block becomes a nested module that implements
  Hermes.Server.Component with type `:tool`. The generated modules
  have proper schema definitions, execute wrappers, and metadata.

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

  ## Generated Module Structure

  Each `tool` block generates a nested module (e.g., `MyApp.Tools.Add`) that:

  - Uses `Hermes.Server.Component, type: :tool`
  - Has `__tool_name__/0` returning the string tool name
  - Has a `schema` block with the user's field declarations
  - Has `__description__/0` returning the tool description (via `@moduledoc`)
  - Has `execute/2` implementing the Hermes tool callback
  - Wraps user return values into proper Hermes responses

  ## Return Value Wrapping

  The user's `execute` function can return:

  - `{:ok, binary}` - wrapped into a text response
  - `{:ok, map | list}` - wrapped into a JSON response
  - `{:ok, other}` - converted to string and wrapped into text response
  - `{:error, message}` - wrapped into an MCP execution error
  """

  @doc """
  Checks if the given module was defined using `ClaudeCode.Tool.Server`.

  Returns `true` if the module exports `__tool_server__/0`, `false` otherwise.
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
      Module.put_attribute(__MODULE__, :_server_name, unquote(name))

      @before_compile ClaudeCode.Tool.Server
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
  Defines a tool within a `ClaudeCode.Tool.Server` module.

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
    schema_block = build_schema_block(field_asts)
    {execute_wrapper, user_execute_def} = build_execute(execute_ast, tool_name_str)

    quote do
      defmodule Module.concat(__MODULE__, unquote(module_name)) do
        @moduledoc unquote(description)

        use Hermes.Server.Component, type: :tool

        alias Hermes.MCP.Error
        alias Hermes.Server.Response

        @doc false
        def __tool_name__, do: unquote(tool_name_str)

        unquote(schema_block)

        unquote(user_execute_def)

        @doc false
        def __wrap_result__({:ok, value}, frame) when is_binary(value) do
          response = Response.text(Response.tool(), value)

          {:reply, response, frame}
        end

        def __wrap_result__({:ok, value}, frame) when is_map(value) or is_list(value) do
          response = Response.json(Response.tool(), value)

          {:reply, response, frame}
        end

        def __wrap_result__({:ok, value}, frame) do
          response = Response.text(Response.tool(), to_string(value))

          {:reply, response, frame}
        end

        def __wrap_result__({:error, message}, frame) when is_binary(message) do
          {:error, Error.execution(message), frame}
        end

        def __wrap_result__({:error, message}, frame) do
          {:error, Error.execution(to_string(message)), frame}
        end

        unquote(execute_wrapper)
      end

      @_tools Module.concat(__MODULE__, unquote(module_name))
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

  # Wraps field AST nodes in a `schema do ... end` block
  defp build_schema_block([]) do
    quote do
      schema do
      end
    end
  end

  defp build_schema_block(field_asts) do
    body =
      case field_asts do
        [single] -> single
        multiple -> {:__block__, [], multiple}
      end

    quote do
      schema do
        unquote(body)
      end
    end
  end

  # Builds the execute/2 wrapper and the renamed user execute function.
  # Detects whether user's execute is arity 1 or 2.
  defp build_execute(execute_defs, _tool_name) do
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
            @impl true
            def execute(params, frame) do
              result = __user_execute__(params)
              __wrap_result__(result, frame)
            end
          end

        _2 ->
          quote do
            @impl true
            def execute(params, frame) do
              result = __user_execute__(params, frame)
              __wrap_result__(result, frame)
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
