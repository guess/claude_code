defmodule ClaudeCode.Hook.PermissionDecision.Deny do
  @moduledoc false
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}
  defstruct [:message, :interrupt]

  def to_wire(%__MODULE__{} = o) do
    %{"behavior" => "deny"}
    |> Output.maybe_put("message", o.message)
    |> Output.maybe_put("interrupt", o.interrupt)
  end
end
