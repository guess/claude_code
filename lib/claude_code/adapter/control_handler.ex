defmodule ClaudeCode.Adapter.ControlHandler do
  @moduledoc false

  alias ClaudeCode.Hook
  alias ClaudeCode.Hook.Output, as: HookOutput
  alias ClaudeCode.Hook.Registry, as: HookRegistry
  alias ClaudeCode.MCP.Router, as: MCPRouter

  require Logger

  @spec handle_mcp_message(String.t(), map(), map()) :: map()
  def handle_mcp_message(server_name, jsonrpc, sdk_mcp_servers) do
    mcp_response =
      case Map.get(sdk_mcp_servers, server_name) do
        nil ->
          %{
            "jsonrpc" => "2.0",
            "id" => jsonrpc["id"],
            "error" => %{"code" => -32_601, "message" => "Server '#{server_name}' not found"}
          }

        {module, assigns} ->
          MCPRouter.handle_request(module, jsonrpc, assigns)
      end

    %{"mcp_response" => mcp_response}
  end

  @spec handle_can_use_tool(map(), HookRegistry.t()) :: map()
  def handle_can_use_tool(_request, %HookRegistry{can_use_tool: nil}), do: %{"behavior" => "allow"}

  def handle_can_use_tool(request, %HookRegistry{can_use_tool: callback}) do
    input =
      request
      |> Map.take(["tool_name", "input", "permission_suggestions", "blocked_path"])
      |> ClaudeCode.MapUtils.safe_atomize_keys()

    result = Hook.invoke(callback, input, nil)

    case result do
      %{__struct__: _} = output -> HookOutput.to_wire(output)
      {:error, reason} -> %{"behavior" => "deny", "message" => "Hook error: #{reason}"}
      _ -> %{"behavior" => "allow"}
    end
  end

  @spec handle_hook_callback(map(), HookRegistry.t()) :: map()
  def handle_hook_callback(request, hook_registry) do
    callback_id = request["callback_id"]
    input = ClaudeCode.MapUtils.safe_atomize_keys(request["input"] || %{})
    tool_use_id = request["tool_use_id"]

    case HookRegistry.lookup(hook_registry, callback_id) do
      {:ok, callback} ->
        result = Hook.invoke(callback, input, tool_use_id)

        case result do
          %{__struct__: _} = output -> HookOutput.to_wire(output)
          _ -> %{}
        end

      :error ->
        Logger.warning("Unknown hook callback ID: #{callback_id}")
        %{}
    end
  end
end
