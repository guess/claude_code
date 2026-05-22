defmodule ClaudeCode.Message.SystemMessage.SessionStateChanged do
  @moduledoc """
  Represents a session state changed system message from the Claude CLI.

  Emitted when the session transitions between states such as idle,
  running, or requires_action.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:session_state_changed`
  - `:state` - The new session state atom (`:idle`, `:running`, or `:requires_action`)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "session_state_changed",
    "state": "idle",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :state]
  defstruct [
    :type,
    :subtype,
    :state,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :session_state_changed,
          state: :idle | :running | :requires_action | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new SessionStateChanged from JSON data.

  The `"state"` string is parsed to an atom (`:idle`, `:running`, or `:requires_action`).
  Unknown values are parsed to `nil`.

  ## Examples

      iex> SessionStateChanged.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "session_state_changed",
      ...>   "state" => "idle",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %SessionStateChanged{type: :system, subtype: :session_state_changed, state: :idle, ...}}

      iex> SessionStateChanged.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{"type" => "system", "subtype" => "session_state_changed", "state" => state, "session_id" => session_id} = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :session_state_changed,
       state: parse_state(state),
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "session_state_changed"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a SessionStateChanged.
  """
  @spec session_state_changed?(any()) :: boolean()
  def session_state_changed?(%__MODULE__{type: :system, subtype: :session_state_changed}), do: true
  def session_state_changed?(_), do: false

  defp parse_state("idle"), do: :idle
  defp parse_state("running"), do: :running
  defp parse_state("requires_action"), do: :requires_action
  defp parse_state(_), do: nil
end
