defmodule ClaudeCode.Hook.Output.PreCompact do
  @moduledoc false
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}
  defstruct [:custom_instructions]

  def to_wire(%__MODULE__{} = o) do
    Output.maybe_put(%{"hookEventName" => "PreCompact"}, "customInstructions", o.custom_instructions)
  end
end
