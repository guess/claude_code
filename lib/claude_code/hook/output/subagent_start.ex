defmodule ClaudeCode.Hook.Output.SubagentStart do
  @moduledoc """
  Hook-specific output for `SubagentStart` events.

  Observation-only — fires when a subagent initializes.

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
    Output.maybe_put(%{"hookEventName" => "SubagentStart"}, "additionalContext", o.additional_context)
  end
end
