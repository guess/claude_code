defmodule ClaudeCode.Adapter.ControlHandlerTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.ControlHandler
  alias ClaudeCode.Hook.Registry, as: HookRegistry

  defmodule AllowHook do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  defmodule DenyHook do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _id), do: {:deny, "Blocked"}
  end

  describe "handle_mcp_message/3" do
    test "dispatches to known MCP server" do
      servers = %{"calc" => {ClaudeCode.TestTools, %{}}}

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "add", "arguments" => %{"x" => 2, "y" => 3}}
      }

      response = ControlHandler.handle_mcp_message("calc", jsonrpc, servers)
      assert %{"mcp_response" => %{"result" => _}} = response
    end

    test "returns error for unknown server" do
      response = ControlHandler.handle_mcp_message("nope", %{"id" => 1}, %{})
      assert %{"mcp_response" => %{"error" => _}} = response
    end
  end

  describe "handle_hook_callback/2" do
    test "invokes registered callback" do
      hooks = %{PreToolUse: [%{hooks: [AllowHook]}]}
      {registry, _wire} = HookRegistry.new(hooks, nil)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"tool_name" => "Read"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert is_map(result)
    end

    test "returns empty map for unknown callback ID" do
      {registry, _wire} = HookRegistry.new(%{}, nil)
      request = %{"callback_id" => "hook_999", "input" => %{}, "tool_use_id" => nil}

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result == %{}
    end
  end

  describe "handle_can_use_tool/2" do
    test "invokes can_use_tool callback and returns wire format" do
      {registry, _wire} = HookRegistry.new(nil, AllowHook)

      request = %{
        "tool_name" => "Read",
        "input" => %{},
        "permission_suggestions" => nil,
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result == %{"behavior" => "allow"}
    end

    test "returns allow when no can_use_tool callback configured" do
      {registry, _wire} = HookRegistry.new(nil, nil)

      request = %{"tool_name" => "Read", "input" => %{}}

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result == %{"behavior" => "allow"}
    end

    test "deny response includes message" do
      {registry, _wire} = HookRegistry.new(nil, DenyHook)

      request = %{"tool_name" => "Bash", "input" => %{}}

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result == %{"behavior" => "deny", "message" => "Blocked"}
    end
  end
end
