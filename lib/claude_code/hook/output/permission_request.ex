defmodule ClaudeCode.Hook.Output.PermissionRequest do
  @moduledoc false
  @type t :: %__MODULE__{}
  defstruct [:decision]

  def to_wire(%__MODULE__{decision: decision}) do
    %{
      "hookEventName" => "PermissionRequest",
      "decision" => decision.__struct__.to_wire(decision)
    }
  end
end
