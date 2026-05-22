defmodule ClaudeCode.Message.SystemMessage.PermissionDenied do
  @moduledoc """
  Represents a permission denied system message from the Claude CLI.

  Emitted when a tool use request is denied by the permission system,
  containing the tool name, tool use ID, and optional denial details.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:permission_denied`
  - `:tool_name` - Name of the tool that was denied
  - `:tool_use_id` - ID of the tool use request that was denied
  - `:agent_id` - Optional agent ID that made the request
  - `:decision_reason_type` - Optional machine-readable denial reason type
  - `:reason` - Optional human-readable denial reason
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "permission_denied",
    "tool_name": "Bash",
    "tool_use_id": "toolu_abc123",
    "agent_id": "agent-1",
    "decision_reason_type": "user_denied",
    "reason": "User rejected this action",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :tool_name, :tool_use_id]
  defstruct [
    :type,
    :subtype,
    :tool_name,
    :tool_use_id,
    :agent_id,
    :decision_reason_type,
    :reason,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :permission_denied,
          tool_name: String.t(),
          tool_use_id: String.t(),
          agent_id: String.t() | nil,
          decision_reason_type: String.t() | nil,
          reason: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new PermissionDenied from JSON data.

  ## Examples

      iex> PermissionDenied.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "permission_denied",
      ...>   "tool_name" => "Bash",
      ...>   "tool_use_id" => "toolu_abc123",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %PermissionDenied{type: :system, subtype: :permission_denied, ...}}

      iex> PermissionDenied.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{
          "type" => "system",
          "subtype" => "permission_denied",
          "tool_name" => tool_name,
          "tool_use_id" => tool_use_id,
          "session_id" => session_id
        } = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :permission_denied,
       tool_name: tool_name,
       tool_use_id: tool_use_id,
       agent_id: json["agent_id"],
       decision_reason_type: json["decision_reason_type"],
       reason: json["reason"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "permission_denied"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a PermissionDenied.
  """
  @spec permission_denied?(any()) :: boolean()
  def permission_denied?(%__MODULE__{type: :system, subtype: :permission_denied}), do: true
  def permission_denied?(_), do: false
end
