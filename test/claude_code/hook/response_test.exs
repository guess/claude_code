defmodule ClaudeCode.Hook.ResponseTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Hook.Response

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
