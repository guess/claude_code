defmodule ClaudeCode.Hook.Output.Async do
  @moduledoc """
  Signals that the hook will respond asynchronously.

  When returned, the CLI proceeds without waiting for the hook result.

  ## Fields

    * `:timeout` - optional timeout in milliseconds for the async operation
  """
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{
          timeout: non_neg_integer() | nil
        }

  defstruct [:timeout]

  def to_wire(%__MODULE__{} = o) do
    Output.maybe_put(%{"async" => true}, "asyncTimeout", o.timeout)
  end
end
