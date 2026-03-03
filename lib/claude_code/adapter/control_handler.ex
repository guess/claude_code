defmodule ClaudeCode.Adapter.ControlHandler do
  @moduledoc false

  alias ClaudeCode.Hook
  alias ClaudeCode.Hook.Registry, as: HookRegistry
  alias ClaudeCode.Hook.Response, as: HookResponse
  alias ClaudeCode.MCP.Router, as: MCPRouter

  require Logger

  @known_hook_key_map %{
    "agent_id" => :agent_id,
    "agent_transcript_path" => :agent_transcript_path,
    "agent_type" => :agent_type,
    "blocked_path" => :blocked_path,
    "custom_instructions" => :custom_instructions,
    "cwd" => :cwd,
    "error" => :error,
    "hook_event" => :hook_event,
    "hook_event_name" => :hook_event_name,
    "hook_id" => :hook_id,
    "hook_name" => :hook_name,
    "input" => :input,
    "is_interrupt" => :is_interrupt,
    "message" => :message,
    "notification_type" => :notification_type,
    "outcome" => :outcome,
    "output" => :output,
    "permission_suggestions" => :permission_suggestions,
    "prompt" => :prompt,
    "session_id" => :session_id,
    "stderr" => :stderr,
    "stdout" => :stdout,
    "stop_hook_active" => :stop_hook_active,
    "title" => :title,
    "tool_input" => :tool_input,
    "tool_name" => :tool_name,
    "tool_response" => :tool_response,
    "transcript_path" => :transcript_path,
    "trigger" => :trigger
  }

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

  @spec handle_hook_callback(map(), HookRegistry.t()) :: map()
  def handle_hook_callback(request, hook_registry) do
    callback_id = request["callback_id"]
    input = atomize_keys(request["input"])
    tool_use_id = request["tool_use_id"]

    case HookRegistry.lookup(hook_registry, callback_id) do
      {:ok, callback} ->
        result = Hook.invoke(callback, input, tool_use_id)
        HookResponse.to_hook_callback_wire(result)

      :error ->
        Logger.warning("Unknown hook callback ID: #{callback_id}")
        %{}
    end
  end

  @spec handle_can_use_tool(map(), HookRegistry.t()) :: map()
  def handle_can_use_tool(request, hook_registry) do
    case hook_registry.can_use_tool do
      nil ->
        %{"behavior" => "allow"}

      callback ->
        input = %{
          tool_name: request["tool_name"],
          input: request["input"],
          permission_suggestions: request["permission_suggestions"],
          blocked_path: request["blocked_path"]
        }

        result = Hook.invoke(callback, input, nil)
        HookResponse.to_can_use_tool_wire(result)
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {Map.get(@known_hook_key_map, key, key), value}
      {key, value} -> {key, value}
    end)
  end

  defp atomize_keys(other), do: other
end
