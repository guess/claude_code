defmodule ClaudeCode.Hook.Output.PostToolUse do
  @moduledoc """
  Hook-specific output for `PostToolUse` events.

  Observation-only — cannot block the tool (it already ran).

  Shorthand: `{:ok, additional_context: "..."}`.

  ## Fields

    * `:additional_context` - extra context injected into the conversation
    * `:updated_mcp_tool_output` - replacement output for MCP tool results
  """
  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{
          additional_context: String.t() | nil,
          updated_mcp_tool_output: term() | nil
        }

  defstruct [:additional_context, :updated_mcp_tool_output]

  def to_wire(%__MODULE__{} = o) do
    %{"hookEventName" => "PostToolUse"}
    |> Output.maybe_put("additionalContext", o.additional_context)
    |> Output.maybe_put("updatedMCPToolOutput", o.updated_mcp_tool_output)
  end
end
