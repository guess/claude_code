defmodule ClaudeCode.Hook.Response do
  @moduledoc false

  @doc """
  Translates a can_use_tool callback return value to CLI wire format.
  """
  @spec to_can_use_tool_wire(term()) :: map()
  def to_can_use_tool_wire(:allow) do
    %{"behavior" => "allow"}
  end

  def to_can_use_tool_wire({:allow, updated_input}) do
    %{"behavior" => "allow", "updatedInput" => updated_input}
  end

  def to_can_use_tool_wire({:allow, updated_input, permissions: updates}) do
    %{"behavior" => "allow", "updatedInput" => updated_input, "updatedPermissions" => updates}
  end

  def to_can_use_tool_wire({:deny, reason}) do
    %{"behavior" => "deny", "message" => reason}
  end

  def to_can_use_tool_wire({:deny, reason, interrupt: true}) do
    %{"behavior" => "deny", "message" => reason, "interrupt" => true}
  end

  def to_can_use_tool_wire({:error, reason}) do
    %{"behavior" => "deny", "message" => "Hook error: #{reason}"}
  end

  @doc """
  Translates a hook_callback return value to CLI wire format.
  """
  @spec to_hook_callback_wire(term()) :: map()
  def to_hook_callback_wire(:ok), do: %{}
  def to_hook_callback_wire(:allow), do: %{}

  def to_hook_callback_wire({:deny, reason}) do
    %{
      "hookSpecificOutput" => %{
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "deny",
        "permissionDecisionReason" => reason
      }
    }
  end

  def to_hook_callback_wire({:allow, updated_input}) do
    %{
      "hookSpecificOutput" => %{
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "allow",
        "updatedInput" => updated_input
      }
    }
  end

  def to_hook_callback_wire({:continue, reason}) do
    %{"continue" => false, "stopReason" => reason}
  end

  def to_hook_callback_wire({:reject, reason}) do
    %{"decision" => "block", "reason" => reason}
  end

  def to_hook_callback_wire({:instructions, text}) do
    %{"hookSpecificOutput" => %{"customInstructions" => text}}
  end

  def to_hook_callback_wire({:error, _reason}), do: %{}
end
