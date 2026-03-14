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

  defmodule MapAllowHook do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    alias ClaudeCode.Hook.Output

    @impl true
    def call(%{hook_event_name: "PreToolUse"}, _id) do
      %Output{
        hook_specific_output: %Output.PreToolUse{
          permission_decision: "allow",
          permission_decision_reason: "Policy approved"
        }
      }
    end

    def call(_input, _id), do: %Output{}
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
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "PreToolUse", "tool_name" => "Read"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert is_map(result)
    end

    test "returns empty map for unknown callback ID" do
      {registry, _wire} = HookRegistry.new(%{})
      request = %{"callback_id" => "hook_999", "input" => %{}, "tool_use_id" => nil}

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result == %{}
    end

    test "map-returning hook produces correct PreToolUse wire format" do
      hooks = %{PreToolUse: [%{hooks: [MapAllowHook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "PreToolUse", "tool_name" => "Read"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result["hookSpecificOutput"]["permissionDecision"] == "allow"
      assert result["hookSpecificOutput"]["permissionDecisionReason"] == "Policy approved"
    end

    test "legacy atom-returning hook still works" do
      hooks = %{PreToolUse: [%{hooks: [AllowHook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "PreToolUse", "tool_name" => "Read"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result["hookSpecificOutput"]["permissionDecision"] == "allow"
    end

    test "shorthand {:deny, opts} produces correct PreToolUse wire format" do
      deny_hook = fn %{hook_event_name: "PreToolUse"}, _id ->
        {:deny, permission_decision_reason: "Blocked by shorthand"}
      end

      hooks = %{PreToolUse: [%{hooks: [deny_hook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "PreToolUse", "tool_name" => "Bash"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
      assert result["hookSpecificOutput"]["permissionDecisionReason"] == "Blocked by shorthand"
    end

    test "shorthand :ok produces empty wire format" do
      ok_hook = fn _input, _id -> :ok end
      hooks = %{PostToolUse: [%{hooks: [ok_hook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "PostToolUse"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result == %{}
    end

    test "shorthand {:halt, opts} produces Stop wire format" do
      halt_hook = fn _input, _id -> {:halt, stop_reason: "Budget left"} end
      hooks = %{Stop: [%{hooks: [halt_hook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "Stop"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result["continue"] == false
      assert result["stopReason"] == "Budget left"
    end

    test "shorthand {:ok, opts} with additional_context produces PostToolUse wire format" do
      ctx_hook = fn _input, _id -> {:ok, additional_context: "Noted"} end
      hooks = %{PostToolUse: [%{hooks: [ctx_hook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "PostToolUse"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result["hookSpecificOutput"]["additionalContext"] == "Noted"
    end

    test "passes through hook_event_name from input" do
      hooks = %{PreToolUse: [%{hooks: [MapAllowHook]}]}
      {registry, _wire} = HookRegistry.new(hooks)

      request = %{
        "callback_id" => "hook_0",
        "input" => %{"hook_event_name" => "PreToolUse", "tool_name" => "Read"},
        "tool_use_id" => nil
      }

      result = ControlHandler.handle_hook_callback(request, registry)
      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
    end
  end

  describe "handle_can_use_tool/2" do
    test "invokes callback and returns allow wire format" do
      callback = fn input, _id ->
        assert input.tool_name
        %ClaudeCode.Hook.PermissionDecision.Allow{}
      end

      {registry, _wire} = HookRegistry.new(%{}, callback)

      request = %{
        "tool_name" => "Bash",
        "input" => %{"command" => "ls"},
        "permission_suggestions" => [],
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result["behavior"] == "allow"
    end

    test "invokes callback and returns deny wire format" do
      callback = fn _input, _id ->
        %ClaudeCode.Hook.PermissionDecision.Deny{message: "Blocked by policy"}
      end

      {registry, _wire} = HookRegistry.new(%{}, callback)

      request = %{
        "tool_name" => "Bash",
        "input" => %{"command" => "rm -rf /"},
        "permission_suggestions" => [],
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result["behavior"] == "deny"
      assert result["message"] == "Blocked by policy"
    end

    test "returns allow when no callback configured" do
      {registry, _wire} = HookRegistry.new(%{})

      request = %{
        "tool_name" => "Bash",
        "input" => %{"command" => "ls"},
        "permission_suggestions" => [],
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result["behavior"] == "allow"
    end

    test "shorthand {:allow, []} returns allow wire format" do
      callback = fn _input, _id -> {:allow, []} end
      {registry, _wire} = HookRegistry.new(%{}, callback)

      request = %{
        "tool_name" => "Bash",
        "input" => %{"command" => "ls"},
        "permission_suggestions" => [],
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result["behavior"] == "allow"
    end

    test "shorthand {:deny, message: ...} returns deny wire format" do
      callback = fn _input, _id -> {:deny, message: "Policy denied"} end
      {registry, _wire} = HookRegistry.new(%{}, callback)

      request = %{
        "tool_name" => "Bash",
        "input" => %{},
        "permission_suggestions" => [],
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result["behavior"] == "deny"
      assert result["message"] == "Policy denied"
    end

    test "shorthand :ok returns allow for can_use_tool" do
      callback = fn _input, _id -> :ok end
      {registry, _wire} = HookRegistry.new(%{}, callback)

      request = %{
        "tool_name" => "Bash",
        "input" => %{},
        "permission_suggestions" => [],
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result["behavior"] == "allow"
    end

    test "handles callback errors gracefully" do
      callback = fn _input, _id -> raise "boom" end
      {registry, _wire} = HookRegistry.new(%{}, callback)

      request = %{
        "tool_name" => "Bash",
        "input" => %{},
        "permission_suggestions" => [],
        "blocked_path" => nil
      }

      result = ControlHandler.handle_can_use_tool(request, registry)
      assert result["behavior"] == "deny"
      assert result["message"] =~ "Hook error"
    end
  end
end
