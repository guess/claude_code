defmodule ClaudeCode.Hook.Output.PostToolUseFailure do
  @moduledoc """
  Hook-specific output for `PostToolUseFailure` events.

  Observation-only — fires after a tool execution fails.

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
    Output.maybe_put(%{"hookEventName" => "PostToolUseFailure"}, "additionalContext", o.additional_context)
  end
end
