defmodule ClaudeCode.Hook.Output.Notification do
  @moduledoc false
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}
  defstruct [:additional_context]

  def to_wire(%__MODULE__{} = o) do
    Output.maybe_put(%{"hookEventName" => "Notification"}, "additionalContext", o.additional_context)
  end
end
