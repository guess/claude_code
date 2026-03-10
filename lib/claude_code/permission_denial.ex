defmodule ClaudeCode.PermissionDenial do
  @moduledoc """
  Represents a permission denial from the Claude CLI.

  Permission denials occur when a tool use is denied by the user or
  permission system during a session.

  Used by `ClaudeCode.Message.ResultMessage` to report which tool uses
  were denied during the conversation.
  """

  @enforce_keys [:tool_name, :tool_use_id]
  defstruct [
    :tool_name,
    :tool_use_id,
    tool_input: %{}
  ]

  @type t :: %__MODULE__{
          tool_name: String.t(),
          tool_use_id: String.t(),
          tool_input: map()
        }

  @doc """
  Parses a permission denial from CLI JSON data.

  ## Examples

      iex> ClaudeCode.PermissionDenial.parse(%{"tool_name" => "Bash", "tool_use_id" => "tu_1", "tool_input" => %{"command" => "rm -rf /"}})
      %ClaudeCode.PermissionDenial{tool_name: "Bash", tool_use_id: "tu_1", tool_input: %{"command" => "rm -rf /"}}

  """
  @spec parse(map()) :: t()
  def parse(denial) when is_map(denial) do
    %__MODULE__{
      tool_name: denial["tool_name"],
      tool_use_id: denial["tool_use_id"],
      tool_input: denial["tool_input"] || %{}
    }
  end
end
