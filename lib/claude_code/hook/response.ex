defmodule ClaudeCode.Hook.Response do
  @moduledoc false

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
