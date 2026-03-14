defmodule ClaudeCode.Hook.Output.PreToolUse do
  @moduledoc """
  Hook-specific output for `PreToolUse` events.

  Controls whether a tool is allowed, denied, or requires user confirmation.

  Shorthand: `{:allow, []}`, `{:deny, permission_decision_reason: "..."}`,
  or `{:ask, []}`.

  ## Fields

    * `:permission_decision` - `"allow"`, `"deny"`, or `"ask"`
    * `:permission_decision_reason` - explanation for the decision
    * `:updated_input` - replacement tool input map
    * `:additional_context` - extra context injected into the conversation
  """
  alias ClaudeCode.Hook.Output

  @type permission_decision :: String.t()

  @type t :: %__MODULE__{
          permission_decision: permission_decision() | nil,
          permission_decision_reason: String.t() | nil,
          updated_input: map() | nil,
          additional_context: String.t() | nil
        }

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
