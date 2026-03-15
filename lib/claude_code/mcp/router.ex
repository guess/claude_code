defmodule ClaudeCode.MCP.Router do
  @moduledoc """
  Dispatches JSONRPC requests to in-process MCP tool server modules.

  Handles the MCP protocol methods (`initialize`, `tools/list`, `tools/call`)
  by routing to the appropriate tool module via the MCP backend.

  This module is called by the adapter when it receives an `mcp_message`
  control request from the CLI for a `type: "sdk"` server.
  """

  alias ClaudeCode.MCP.Backend.Hermes, as: Backend

  @doc """
  Handles a JSONRPC request for the given tool server module.

  Returns a JSONRPC response map ready for JSON encoding.

  ## Parameters

    * `server_module` - A module that uses `ClaudeCode.MCP.Server` and
      exports `__tool_server__/0`
    * `message` - A decoded JSONRPC request map with `"method"` key
    * `assigns` - Optional map of assigns to set on the Hermes frame
      (available to tools that define `execute/2`)

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
  @spec handle_request(module(), map(), map()) :: map()
  def handle_request(server_module, message, assigns \\ %{})

  def handle_request(server_module, %{"method" => method} = message, assigns) do
    case method do
      "initialize" ->
        jsonrpc_result(message, %{
          "protocolVersion" => "2024-11-05",
          "capabilities" => %{"tools" => %{}},
          "serverInfo" => Backend.server_info(server_module)
        })

      "notifications/" <> _ ->
        # Notifications have no "id" field in JSONRPC 2.0
        %{"jsonrpc" => "2.0", "result" => %{}}

      "tools/list" ->
        tools = Backend.list_tools(server_module)
        jsonrpc_result(message, %{"tools" => tools})

      "tools/call" ->
        %{"params" => %{"name" => name, "arguments" => args}} = message

        case Backend.call_tool(server_module, name, args, assigns) do
          {:ok, result} ->
            jsonrpc_result(message, result)

          {:error, msg} ->
            jsonrpc_error(message, -32_601, msg)

          {:validation_error, msg} ->
            jsonrpc_error(message, -32_602, msg)
        end

      _ ->
        jsonrpc_error(message, -32_601, "Method '#{method}' not supported")
    end
  end

  defp jsonrpc_result(%{"id" => id}, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp jsonrpc_error(%{"id" => id}, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
