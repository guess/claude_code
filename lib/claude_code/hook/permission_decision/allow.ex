defmodule ClaudeCode.Hook.PermissionDecision.Allow do
  @moduledoc """
  Allows a tool to execute, optionally with modified input or updated permissions.

  Returned from `:can_use_tool` callbacks and `PermissionRequest` hooks.

  Shorthand: `{:allow, updated_input: %{...}}` or bare `:ok`.

  ## Fields

    * `:updated_input` - replacement tool input map (overrides the original)
    * `:updated_permissions` - list of permission rules to apply
  """
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{
          updated_input: map() | nil,
          updated_permissions: [map()] | nil
        }

  defstruct [:updated_input, :updated_permissions]

  def to_wire(%__MODULE__{} = o) do
    %{"behavior" => "allow"}
    |> Output.maybe_put("updatedInput", o.updated_input)
    |> Output.maybe_put("updatedPermissions", o.updated_permissions)
  end
end
