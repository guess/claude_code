defmodule ClaudeCode.Hook.ResponseTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Hook.Response

  describe "to_can_use_tool_wire/1" do
    test "translates :allow" do
      assert %{"behavior" => "allow"} = Response.to_can_use_tool_wire(:allow)
    end

    test "translates {:allow, updated_input}" do
      result = Response.to_can_use_tool_wire({:allow, %{"command" => "ls"}})
      assert result["behavior"] == "allow"
      assert result["updatedInput"] == %{"command" => "ls"}
    end

    test "translates {:allow, updated_input, permissions: updates}" do
      updates = [%{type: :add_rules, rules: [%{tool_name: "Bash", rule_content: "allow ls"}]}]
      result = Response.to_can_use_tool_wire({:allow, %{}, permissions: updates})
      assert result["behavior"] == "allow"
      assert result["updatedInput"] == %{}
      assert is_list(result["updatedPermissions"])
    end

    test "translates {:deny, reason}" do
      result = Response.to_can_use_tool_wire({:deny, "Not allowed"})
      assert result["behavior"] == "deny"
      assert result["message"] == "Not allowed"
      refute Map.has_key?(result, "interrupt")
    end

    test "translates {:deny, reason, interrupt: true}" do
      result = Response.to_can_use_tool_wire({:deny, "Critical", interrupt: true})
      assert result["behavior"] == "deny"
      assert result["message"] == "Critical"
      assert result["interrupt"] == true
    end

    test "translates {:error, reason} as deny" do
      result = Response.to_can_use_tool_wire({:error, "callback crashed"})
      assert result["behavior"] == "deny"
      assert result["message"] =~ "callback crashed"
    end
  end

  describe "to_hook_callback_wire/1" do
    test "translates :ok as empty response" do
      assert %{} = Response.to_hook_callback_wire(:ok)
    end

    test "translates :allow for PreToolUse hooks" do
      result = Response.to_hook_callback_wire(:allow)
      assert result == %{}
    end

    test "translates {:deny, reason} for PreToolUse hooks" do
      result = Response.to_hook_callback_wire({:deny, "blocked"})
      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
      assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
      assert result["hookSpecificOutput"]["permissionDecisionReason"] == "blocked"
    end

    test "translates {:continue, reason} for Stop hooks" do
      result = Response.to_hook_callback_wire({:continue, "Keep going"})
      assert result["continue"] == false
      assert result["stopReason"] == "Keep going"
    end

    test "translates {:reject, reason} for UserPromptSubmit hooks" do
      result = Response.to_hook_callback_wire({:reject, "Bad prompt"})
      assert result["decision"] == "block"
      assert result["reason"] == "Bad prompt"
    end

    test "translates {:instructions, text} for PreCompact hooks" do
      result = Response.to_hook_callback_wire({:instructions, "Remember X"})
      assert result["hookSpecificOutput"]["customInstructions"] == "Remember X"
    end

    test "translates {:error, reason} as empty response" do
      result = Response.to_hook_callback_wire({:error, "crash"})
      assert result == %{}
    end
  end
end
