defmodule ClaudeCode.Hook.Output.Async do
  @moduledoc false
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}
  defstruct [:timeout]

  def to_wire(%__MODULE__{} = o) do
    Output.maybe_put(%{"async" => true}, "asyncTimeout", o.timeout)
  end
end
