defmodule ClaudeCode.Hook.Output.Notification do
  @moduledoc """
  Hook-specific output for `Notification` events.

  Observation-only — fires when the agent sends status messages
  (permission prompts, idle prompts, auth success, etc.).

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
    Output.maybe_put(%{"hookEventName" => "Notification"}, "additionalContext", o.additional_context)
  end
end
