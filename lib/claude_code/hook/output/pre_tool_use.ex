defmodule ClaudeCode.Hook.Output.PreToolUse do
  @moduledoc false
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}

  defstruct [
    :permission_decision,
    :permission_decision_reason,
    :updated_input,
    :additional_context
  ]

  def to_wire(%__MODULE__{} = o) do
    %{"hookEventName" => "PreToolUse"}
    |> Output.maybe_put("permissionDecision", o.permission_decision)
    |> Output.maybe_put("permissionDecisionReason", o.permission_decision_reason)
    |> Output.maybe_put("updatedInput", o.updated_input)
    |> Output.maybe_put("additionalContext", o.additional_context)
  end
end
