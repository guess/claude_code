defmodule ClaudeCode.MCP.Router do
  @moduledoc """
  Dispatches JSONRPC requests to in-process MCP tool server modules.

  Handles the MCP protocol methods (`initialize`, `tools/list`, `tools/call`)
  by routing to the appropriate tool module's `execute/2` callback.

  This module is called by the adapter when it receives an `mcp_message`
  control request from the CLI for a `type: "sdk"` server.
  """

  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @doc """
  Handles a JSONRPC request for the given tool server module.

  Returns a JSONRPC response map ready for JSON encoding.

  ## Parameters

    * `server_module` - A module that uses `ClaudeCode.Tool.Server` and
      exports `__tool_server__/0`
    * `message` - A decoded JSONRPC request map with `"method"` key

  ## Supported Methods

    * `"initialize"` - Returns protocol version, capabilities, and server info
    * `"notifications/initialized"` - Acknowledges initialization (returns empty result)
    * `"tools/list"` - Returns all registered tools with their schemas
    * `"tools/call"` - Dispatches to the named tool's `execute/2` callback

  ## Examples

      iex> message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
      iex> Router.handle_request(MyApp.Tools, message)
      %{"jsonrpc" => "2.0", "id" => 1, "result" => %{"protocolVersion" => "2024-11-05", ...}}
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
        jsonrpc_error(message, -32_601, "Method '#{method}' not supported")
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
        jsonrpc_error(message, -32_601, "Tool '#{name}' not found")

      module ->
        atom_args = atomize_keys(args)
        frame = Frame.new()

        try do
          case module.execute(atom_args, frame) do
            {:reply, response, _frame} ->
              jsonrpc_result(message, Response.to_protocol(response))

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

  # Converts string keys to atoms for tool parameter maps.
  #
  # This is safe because keys come from tool schema field declarations,
  # which are a bounded set of atoms defined at compile time.
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
