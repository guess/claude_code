defmodule ClaudeCode.Message.SystemMessage.Status do
  @moduledoc """
  Represents a status message from the Claude CLI.

  Emitted when the CLI transitions between processing states, such as
  thinking, tool use, or other activity phases.

  ## Fields

  - `:status` - The current status string (e.g., "thinking", "tool_use")
  - `:permission_mode` - The current permission mode (optional)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "status",
    "status": "thinking",
    "permissionMode": "default",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :status]
  defstruct [
    :type,
    :subtype,
    :status,
    :permission_mode,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :status,
          status: String.t(),
          permission_mode: atom() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new Status from JSON data.

  ## Examples

      iex> Status.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "status",
      ...>   "status" => "thinking",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %Status{type: :system, subtype: :status, ...}}

      iex> Status.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "status", "status" => status, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :status,
       status: status,
       permission_mode: ClaudeCode.Session.PermissionMode.parse(json["permission_mode"]),
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "status"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a Status.
  """
  @spec status?(any()) :: boolean()
  def status?(%__MODULE__{type: :system, subtype: :status}), do: true
  def status?(_), do: false
end
