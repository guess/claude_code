defmodule ClaudeCode.Hook.Output.UserPromptSubmit do
  @moduledoc """
  Hook-specific output for `UserPromptSubmit` events.

  Can inject additional context when a user submits a prompt.

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
    Output.maybe_put(%{"hookEventName" => "UserPromptSubmit"}, "additionalContext", o.additional_context)
  end
end
