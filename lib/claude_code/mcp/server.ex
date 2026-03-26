defmodule ClaudeCode.MCP.Server do
  @moduledoc """
  Macro for generating MCP tool modules from a concise DSL.

  Each `tool` block becomes a nested module that uses Anubis.Server.Component
  with schema definitions, execute wrappers, and metadata.

  ## Usage

      defmodule MyApp.Tools do
        use ClaudeCode.MCP.Server, name: "my-tools"

        tool :add do
          description "Add two numbers"

          field :x, :integer, required: true
          field :y, :integer, required: true

          def execute(%{x: x, y: y}) do
            {:ok, "\#{x + y}"}
          end
        end

        tool :get_time do
          description "Get current UTC time"

          def execute(_params) do
            {:ok, DateTime.utc_now() |> to_string()}
          end
        end
      end

  ## Generated Module Structure

  Each `tool` block generates a nested module (e.g., `MyApp.Tools.Add`) that:

  - Uses Anubis.Server.Component with `type: :tool`
  - Has a `schema` block for Peri-validated input parameters
  - Has `input_schema/0` returning JSON Schema (via Anubis Component)
  - Has `execute/2` accepting `(params, frame)` and delegating to the user's execute function

  ## Execute Function

  The user's `execute` function can be arity 1 or 2:

  - `def execute(params)` — receives validated params only
  - `def execute(params, frame)` — receives params and `Anubis.Server.Frame.t()`
    (access assigns via `frame.assigns`)

  ## Return Values

  The user's `execute` function can return:

  - `{:ok, binary}` — returned as text content
  - `{:ok, map | list}` — returned as JSON content
  - `{:ok, other}` — converted to string and returned as text content
  - `{:error, message}` — returned as error content
  - `{:ok, value, frame}` — text/JSON content with updated frame
  - `{:error, message, frame}` — error content with updated frame
  - `{:noreply, frame}` — no content, updated frame
  - `{:reply, %Response{}, frame}` — native Anubis response (passthrough)
  - `{:error, %Error{}, frame}` — native Anubis error (passthrough)
  """

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias Anubis.Server.Response

  @doc """
  Checks if the given module was defined using `ClaudeCode.MCP.Server`.

  Returns `true` if the module exports `__tool_server__/0`, `false` otherwise.
  """
  @spec sdk_server?(module()) :: boolean()
  def sdk_server?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__tool_server__, 0)
  end

  @doc """
  Converts a value to an `Anubis.Server.Response` for a tool result.

  Used by generated execute wrappers to translate SDK return values.
  """
  @spec to_response(term()) :: Response.t()
  def to_response(v) when is_binary(v), do: Response.text(Response.tool(), v)
  def to_response(v) when is_map(v) or is_list(v), do: Response.json(Response.tool(), v)
  def to_response(v), do: Response.text(Response.tool(), to_string(v))

  @doc """
  Converts an error message to an `Anubis.Server.Response` with `isError: true`.

  Used by generated execute wrappers to translate SDK error return values.
  """
  @spec to_error_response(term()) :: Response.t()
  def to_error_response(msg) when is_binary(msg), do: Response.error(Response.tool(), msg)
  def to_error_response(msg), do: Response.error(Response.tool(), to_string(msg))

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      import ClaudeCode.MCP.Server, only: [tool: 2, description: 1]

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
  Sets the description for a tool. Must be used inside a `tool` block.

  The description is extracted at compile time from the AST — this macro
  exists so that `import` makes `description/1` available in tool blocks.

  ## Example

      tool :add do
        description "Add two numbers"

        field :x, :integer, required: true

        def execute(%{x: x, y: y}) do
          {:ok, "\#{x + y}"}
        end
      end
  """
  defmacro description(_text) do
    # Intentionally empty — the description string is extracted from the AST
    # by split_tool_block/1 at compile time, not via macro expansion.
    :ok
  end

  @doc """
  Defines a tool within a `ClaudeCode.MCP.Server` module.

  ## Parameters

  - `name` - atom name for the tool (e.g., `:add`)
  - `block` - the tool body containing a `description`, optional `field` declarations,
    and a `def execute` function

  ## Examples

      tool :add do
        description "Add two numbers"

        field :x, :integer, required: true
        field :y, :integer, required: true

        def execute(%{x: x, y: y}) do
          {:ok, "\#{x + y}"}
        end
      end
  """
  defmacro tool(name, do: block) do
    module_name = name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
    tool_name_str = Atom.to_string(name)

    {description_text, field_asts, execute_ast} = split_tool_block(block)
    schema_def = build_schema(field_asts)
    {execute_wrapper, user_execute_def} = build_execute(execute_ast)

    quote do
      defmodule Module.concat(__MODULE__, unquote(module_name)) do
        @moduledoc unquote(description_text)
        use Anubis.Server.Component, type: :tool

        unquote(schema_def)

        @doc false
        def __tool_name__, do: unquote(tool_name_str)

        @impl true
        def description, do: unquote(description_text)

        unquote(user_execute_def)

        unquote(execute_wrapper)
      end

      @_tools Module.concat(__MODULE__, unquote(module_name))
    end
  end

  # -- Private helpers for AST manipulation --

  # Splits the tool block AST into {description_text, field_asts, execute_asts}.
  # The description text is extracted at compile time from the `description "..."` call.
  defp split_tool_block({:__block__, _, statements}) do
    {descriptions, rest} = Enum.split_with(statements, &description_call?/1)
    {fields, executes} = Enum.split_with(rest, &(not execute_def?(&1)))

    description_text =
      case descriptions do
        [{:description, _, [text]}] when is_binary(text) -> text
        [] -> raise ArgumentError, "tool block must include a `description`"
        _ -> raise ArgumentError, "tool block must include exactly one `description` with a string literal"
      end

    {description_text, fields, executes}
  end

  # Single statement block (just a def execute, no fields)
  defp split_tool_block(single) do
    cond do
      execute_def?(single) -> raise ArgumentError, "tool block must include a `description`"
      description_call?(single) -> raise ArgumentError, "tool block must include a `def execute`"
      true -> raise ArgumentError, "tool block must include a `description` and `def execute`"
    end
  end

  # Checks if an AST node is a `description "..."` call
  defp description_call?({:description, _, [_]}), do: true
  defp description_call?(_), do: false

  # Checks if an AST node is a `def execute(...)` definition
  defp execute_def?({:def, _, [{:execute, _, _} | _]}), do: true
  defp execute_def?(_), do: false

  # Builds the schema block from field declarations.
  # When there are fields, emits a `schema do ... end` block using Anubis Component's macros.
  # When there are no fields, defines __mcp_raw_schema__/0 directly for input_schema/0.
  defp build_schema([]) do
    quote do
      @doc false
      def __mcp_raw_schema__, do: %{}
    end
  end

  defp build_schema(field_asts) do
    quote do
      schema do
        (unquote_splicing(field_asts))
      end
    end
  end

  @doc """
  Translates a user's execute return value into a native Anubis response tuple.

  This is called by the generated `execute/2` wrapper in each tool module.
  """
  @spec wrap_result(term(), Frame.t()) ::
          {:reply, Response.t(), Frame.t()}
          | {:noreply, Frame.t()}
          | {:error, Error.t(), Frame.t()}
  def wrap_result(result, frame) do
    case result do
      # Native Anubis passthrough (matched first — no guards needed below)
      {:reply, %Response{} = resp, updated_frame} -> {:reply, resp, updated_frame}
      {:error, %Error{} = error, updated_frame} -> {:error, error, updated_frame}
      {:noreply, updated_frame} -> {:noreply, updated_frame}
      # SDK returns
      {:ok, v} -> {:reply, to_response(v), frame}
      {:ok, v, updated_frame} -> {:reply, to_response(v), updated_frame}
      {:error, msg} -> {:reply, to_error_response(msg), frame}
      {:error, msg, updated_frame} -> {:reply, to_error_response(msg), updated_frame}
    end
  end

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

    call_ast =
      case arity do
        1 -> quote(do: __user_execute__(params))
        _2 -> quote(do: __user_execute__(params, frame))
      end

    wrapper =
      quote do
        @impl true
        def execute(params, frame) do
          unquote(__MODULE__).wrap_result(unquote(call_ast), frame)
        rescue
          e ->
            {:reply, unquote(__MODULE__).to_error_response("Tool error: #{Exception.message(e)}"), frame}
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
