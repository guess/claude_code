if Code.ensure_loaded?(Anubis.Server) do
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

          case validate_params(module, atom_params) do
            :ok -> execute_tool(module, atom_params, assigns)
            {:error, error_msg} -> {:validation_error, "Invalid params: #{error_msg}"}
          end
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

    defp validate_params(module, params) do
      schema = module.input_schema()
      properties = schema["properties"] || %{}
      required = schema["required"] || []

      errors =
        Enum.flat_map(required, fn field ->
          key = String.to_existing_atom(field)
          if Map.has_key?(params, key), do: [], else: ["#{field} is required"]
        end) ++
          Enum.flat_map(params, fn {key, value} ->
            key_str = Atom.to_string(key)

            case Map.get(properties, key_str) do
              nil -> []
              prop_schema -> validate_type(key_str, value, prop_schema)
            end
          end)

      case errors do
        [] -> :ok
        errors -> {:error, Enum.join(errors, ", ")}
      end
    end

    defp validate_type(name, value, %{"type" => "integer"}) when not is_integer(value),
      do: ["#{name}: expected integer, got #{inspect(value)}"]

    defp validate_type(name, value, %{"type" => "string"}) when not is_binary(value),
      do: ["#{name}: expected string, got #{inspect(value)}"]

    defp validate_type(name, value, %{"type" => "number"}) when not is_number(value),
      do: ["#{name}: expected number, got #{inspect(value)}"]

    defp validate_type(name, value, %{"type" => "boolean"}) when not is_boolean(value),
      do: ["#{name}: expected boolean, got #{inspect(value)}"]

    defp validate_type(_name, _value, _schema), do: []

    defp execute_tool(module, params, assigns) do
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
