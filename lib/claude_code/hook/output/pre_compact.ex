defmodule ClaudeCode.Hook.Output.PreCompact do
  @moduledoc """
  Hook-specific output for `PreCompact` events.

  Fires before conversation compaction, allowing custom instructions
  to guide what the compaction preserves.

  Shorthand: `{:ok, custom_instructions: "..."}`.

  ## Fields

    * `:custom_instructions` - instructions for the compaction process
  """
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{
          custom_instructions: String.t() | nil
        }

  defstruct [:custom_instructions]

  def to_wire(%__MODULE__{} = o) do
    Output.maybe_put(%{"hookEventName" => "PreCompact"}, "customInstructions", o.custom_instructions)
  end
end
