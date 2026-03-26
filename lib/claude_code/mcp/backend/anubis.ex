if Code.ensure_loaded?(Anubis.Server) do
  defmodule ClaudeCode.MCP.Backend.Anubis do
    @moduledoc false
    @behaviour ClaudeCode.MCP.Backend

    alias Anubis.MCP.Error
    alias Anubis.Server.Component
    alias Anubis.Server.Component.Schema
    alias Anubis.Server.Frame
    alias Anubis.Server.Response
    alias ClaudeCode.MCP.Server, as: MCPServer

    @impl true
    def list_tools(server_module) do
      %{tools: tool_modules} = server_module.__tool_server__()

      Enum.map(tool_modules, fn module ->
        %{
          "name" => module.__tool_name__(),
          "description" => Component.get_description(module),
          "inputSchema" => module.input_schema()
        }
      end)
    end

    @impl true
    def call_tool(server_module, tool_name, params, assigns) do
      %{tools: tool_modules} = server_module.__tool_server__()

      case Enum.find(tool_modules, &(&1.__tool_name__() == tool_name)) do
        nil ->
          {:error, Error.protocol(:method_not_found, %{message: "Tool '#{tool_name}' not found"})}

        module ->
          atom_params = ClaudeCode.MapUtils.safe_atomize_keys(params)
          frame = Frame.new(assigns)

          with :ok <- validate_with_peri(module, atom_params) do
            execute_tool(module, atom_params, frame)
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
        not MCPServer.sdk_server?(module) and
        has_behaviour?(module, Anubis.Server)
    end

    defp has_behaviour?(module, behaviour) do
      :attributes
      |> module.module_info()
      |> Keyword.get_values(:behaviour)
      |> List.flatten()
      |> Enum.member?(behaviour)
    end

    defp validate_with_peri(module, params) do
      if function_exported?(module, :mcp_schema, 1) do
        case module.mcp_schema(params) do
          {:ok, _validated} ->
            :ok

          {:error, errors} ->
            message = Schema.format_errors(errors)
            {:error, Error.protocol(:invalid_params, %{message: message})}
        end
      else
        :ok
      end
    end

    defp execute_tool(module, params, frame) do
      case module.execute(params, frame) do
        {:reply, %Response{} = response, _frame} ->
          {:ok, Response.to_protocol(response)}

        {:noreply, _frame} ->
          {:ok, %{"content" => [], "isError" => false}}

        {:error, %Error{} = error, _frame} ->
          {:error, error}
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
