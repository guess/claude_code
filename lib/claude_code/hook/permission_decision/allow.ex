defmodule ClaudeCode.Hook.PermissionDecision.Allow do
  @moduledoc false
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}
  defstruct [:updated_input, :updated_permissions]

  def to_wire(%__MODULE__{} = o) do
    %{"behavior" => "allow"}
    |> Output.maybe_put("updatedInput", o.updated_input)
    |> Output.maybe_put("updatedPermissions", o.updated_permissions)
  end
end
