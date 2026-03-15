if Code.ensure_loaded?(Hermes.Server) do
  defmodule ClaudeCode.MCP.Backend.Hermes do
    @moduledoc false
    @behaviour ClaudeCode.MCP.Backend

    alias ClaudeCode.MCP.Server, as: MCPServer
    alias Hermes.Server.Component
    alias Hermes.Server.Component.Schema
    alias Hermes.Server.Frame
    alias Hermes.Server.Response

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
            {:ok, validated} ->
              execute_tool(module, validated, assigns)

            {:error, errors} ->
              error_msg = Schema.format_errors(errors)
              {:validation_error, "Invalid params: #{error_msg}"}
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

    # -- Private helpers --

    defp validate_params(module, params) do
      raw_schema = module.__mcp_raw_schema__()
      peri_schema = Component.__clean_schema_for_peri__(raw_schema)
      Peri.validate(peri_schema, params)
    end

    defp execute_tool(module, params, assigns) do
      frame = Frame.new(assigns)

      try do
        case module.execute(params, frame) do
          {:reply, response, _frame} ->
            {:ok, Response.to_protocol(response)}

          {:error, %{message: error_msg}, _frame} ->
            {:ok,
             %{
               "content" => [%{"type" => "text", "text" => to_string(error_msg)}],
               "isError" => true
             }}
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
end
