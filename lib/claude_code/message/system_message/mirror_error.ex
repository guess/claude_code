defmodule ClaudeCode.Message.SystemMessage.MirrorError do
  @moduledoc """
  Represents a mirror error system message from the Claude CLI.

  Emitted when a mirroring operation fails, containing the error message
  and the key identifying the mirror target.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:mirror_error`
  - `:error` - Error message string
  - `:key` - Raw map identifying the mirror target (has `project_key`, `session_id`, and optional `subpath` keys after normalization)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "mirror_error",
    "error": "Connection refused",
    "key": {"projectKey": "proj_abc", "sessionId": "sess_xyz", "subpath": "logs"},
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :error]
  defstruct [
    :type,
    :subtype,
    :error,
    :key,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :mirror_error,
          error: String.t(),
          key: map() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new MirrorError from JSON data.

  The `"key"` object is stored as a raw map (with snake_case keys after normalization).

  ## Examples

      iex> MirrorError.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "mirror_error",
      ...>   "error" => "Connection refused",
      ...>   "key" => %{"project_key" => "proj_abc", "session_id" => "sess_xyz"},
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %MirrorError{type: :system, subtype: :mirror_error, ...}}

      iex> MirrorError.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "mirror_error", "error" => error, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :mirror_error,
       error: error,
       key: json["key"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "mirror_error"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a MirrorError.
  """
  @spec mirror_error?(any()) :: boolean()
  def mirror_error?(%__MODULE__{type: :system, subtype: :mirror_error}), do: true
  def mirror_error?(_), do: false
end
