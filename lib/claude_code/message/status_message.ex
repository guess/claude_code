defmodule ClaudeCode.Message.StatusMessage do
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
  Creates a new StatusMessage from JSON data.

  ## Examples

      iex> StatusMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "status",
      ...>   "status" => "thinking",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %StatusMessage{type: :system, subtype: :status, ...}}

      iex> StatusMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "status", "status" => status, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :status,
       status: status,
       permission_mode: ClaudeCode.Message.parse_permission_mode(json["permissionMode"]),
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "status"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a StatusMessage.
  """
  @spec status_message?(any()) :: boolean()
  def status_message?(%__MODULE__{type: :system, subtype: :status}), do: true
  def status_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.StatusMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.StatusMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
