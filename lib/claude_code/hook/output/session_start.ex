defmodule ClaudeCode.Hook.Output.SessionStart do
  @moduledoc """
  Hook-specific output for `SessionStart` events.

  Observation-only — fires when the session initializes.

  Shorthand: `{:ok, additional_context: "..."}`.

  ## Fields

    * `:additional_context` - extra context injected into the conversation
  """
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{
          additional_context: String.t() | nil
        }

  defstruct [:additional_context]

  def to_wire(%__MODULE__{} = o) do
    Output.maybe_put(%{"hookEventName" => "SessionStart"}, "additionalContext", o.additional_context)
  end
end
