defmodule ClaudeCode.Hook.PermissionDecision.Deny do
  @moduledoc """
  Denies a tool from executing, with an optional message and interrupt flag.

  Returned from `:can_use_tool` callbacks and `PermissionRequest` hooks.

  Shorthand: `{:deny, message: "reason"}`.

  ## Fields

    * `:message` - explanation shown to the user for the denial
    * `:interrupt` - when `true`, interrupts the agent instead of continuing
  """
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{
          message: String.t() | nil,
          interrupt: boolean() | nil
        }

  defstruct [:message, :interrupt]

  def to_wire(%__MODULE__{} = o) do
    %{"behavior" => "deny"}
    |> Output.maybe_put("message", o.message)
    |> Output.maybe_put("interrupt", o.interrupt)
  end
end
