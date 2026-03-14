defmodule ClaudeCode.Hook.Output.PostToolUse do
  @moduledoc false
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}
  defstruct [:additional_context, :updated_mcp_tool_output]

  def to_wire(%__MODULE__{} = o) do
    %{"hookEventName" => "PostToolUse"}
    |> Output.maybe_put("additionalContext", o.additional_context)
    |> Output.maybe_put("updatedMCPToolOutput", o.updated_mcp_tool_output)
  end
end
