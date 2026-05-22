defmodule ClaudeCode.Message.SystemMessage.Notification do
  @moduledoc """
  Represents a notification system message from the Claude CLI.

  Emitted to surface user-facing notifications with varying priority levels.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:notification`
  - `:key` - Unique identifier key for the notification
  - `:text` - Human-readable notification text
  - `:priority` - Priority atom (`:low`, `:medium`, `:high`, or `:immediate`)
  - `:color` - Optional display color hint
  - `:timeout_ms` - Optional auto-dismiss timeout in milliseconds
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "notification",
    "key": "rate_limit_warning",
    "text": "Approaching rate limit",
    "priority": "high",
    "color": "yellow",
    "timeout_ms": 5000,
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :key, :text]
  defstruct [
    :type,
    :subtype,
    :key,
    :text,
    :priority,
    :color,
    :timeout_ms,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :notification,
          key: String.t(),
          text: String.t(),
          priority: :low | :medium | :high | :immediate | nil,
          color: String.t() | nil,
          timeout_ms: integer() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new Notification from JSON data.

  The `"priority"` string is parsed to an atom (`:low`, `:medium`, `:high`, or `:immediate`).
  Unknown values are parsed to `nil`.

  ## Examples

      iex> Notification.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "notification",
      ...>   "key" => "rate_limit_warning",
      ...>   "text" => "Approaching rate limit",
      ...>   "priority" => "high",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %Notification{type: :system, subtype: :notification, priority: :high, ...}}

      iex> Notification.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{"type" => "system", "subtype" => "notification", "key" => key, "text" => text, "session_id" => session_id} =
          json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :notification,
       key: key,
       text: text,
       priority: parse_priority(json["priority"]),
       color: json["color"],
       timeout_ms: json["timeout_ms"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "notification"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a Notification.
  """
  @spec notification?(any()) :: boolean()
  def notification?(%__MODULE__{type: :system, subtype: :notification}), do: true
  def notification?(_), do: false

  defp parse_priority("low"), do: :low
  defp parse_priority("medium"), do: :medium
  defp parse_priority("high"), do: :high
  defp parse_priority("immediate"), do: :immediate
  defp parse_priority(_), do: nil
end
