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

  @spec handle_can_use_tool(map(), HookRegistry.t(), map()) :: map()
  def handle_can_use_tool(request, registry, context \\ %{})

  def handle_can_use_tool(_request, %HookRegistry{can_use_tool: nil}, _context), do: %{"behavior" => "allow"}

  def handle_can_use_tool(request, %HookRegistry{can_use_tool: callback}, context) do
    input =
      request
      |> Map.delete("subtype")
      |> ClaudeCode.MapUtils.safe_atomize_keys()
      |> enrich_with_context(context)

    tool_use_id = input[:tool_use_id]
    result = Hook.invoke(callback, input, tool_use_id)

    case result do
      {:error, reason} -> %{"behavior" => "deny", "message" => "Hook error: #{reason}"}
      value -> value |> HookOutput.coerce_permission() |> HookOutput.to_wire()
    end
  end

  # Merge adapter-level context (cwd, session_id) into the callback input.
  # Only adds keys that have non-nil values and aren't already present
  # (CLI-provided values take precedence).
  defp enrich_with_context(input, context) do
    context
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.merge(input)
  end

  @spec handle_hook_callback(map(), HookRegistry.t()) :: {:ok, map()} | {:error, String.t()}
  def handle_hook_callback(request, hook_registry) do
    input = ClaudeCode.MapUtils.safe_atomize_keys(request["input"] || %{})

    with {:ok, callback} <- lookup_callback(hook_registry, request["callback_id"]),
         {:ok, value} <- invoke_callback(callback, input, request["tool_use_id"]) do
      {:ok, value |> HookOutput.coerce(input[:hook_event_name]) |> HookOutput.to_wire()}
    end
  end

  defp lookup_callback(registry, callback_id) do
    case HookRegistry.lookup(registry, callback_id) do
      {:ok, _callback} = ok -> ok
      :error -> {:error, "Unknown hook callback ID: #{callback_id}"}
    end
  end

  defp invoke_callback(callback, input, tool_use_id) do
    case Hook.invoke(callback, input, tool_use_id) do
      {:error, reason} -> {:error, "Hook callback raised: #{reason}"}
      value -> {:ok, value}
    end
  end
end
