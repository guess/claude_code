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

  @doc false
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
  # Detects whether user's execute is arity 1 or 2.
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
