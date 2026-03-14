defmodule ClaudeCode.Hook.Output.PermissionRequest do
  @moduledoc """
  Hook-specific output for `PermissionRequest` events.

  Wraps a `ClaudeCode.Hook.PermissionDecision.Allow` or
  `ClaudeCode.Hook.PermissionDecision.Deny` decision for when a tool
  requires permission at the permission-prompt stage.

  Shorthand: `{:allow, updated_input: %{...}}` or `{:deny, message: "..."}`.

  ## Fields

    * `:decision` - a `PermissionDecision.Allow` or `PermissionDecision.Deny` struct
  """
  @type t :: %__MODULE__{
          decision:
            ClaudeCode.Hook.PermissionDecision.Allow.t()
            | ClaudeCode.Hook.PermissionDecision.Deny.t()
        }

  defstruct [:decision]

  def to_wire(%__MODULE__{decision: decision}) do
    %{
      "hookEventName" => "PermissionRequest",
      "decision" => decision.__struct__.to_wire(decision)
    }
  end
end
