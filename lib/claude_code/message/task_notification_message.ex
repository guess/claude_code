defmodule ClaudeCode.Message.TaskNotificationMessage do
  @moduledoc """
  Represents a task notification system message from the Claude CLI.

  Emitted when a background task reaches a terminal state (completed, failed, or stopped).
  Contains the task output summary and final usage statistics.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:task_notification`
  - `:task_id` - Unique identifier for the task
  - `:tool_use_id` - Associated tool use block ID (optional)
  - `:status` - Terminal status atom (`:completed`, `:failed`, or `:stopped`)
  - `:output_file` - Path to the task output file
  - `:summary` - Human-readable summary of the task result
  - `:usage` - Final token and tool usage stats (optional map with `total_tokens`, `tool_uses`, `duration_ms`)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "task_notification",
    "task_id": "task_abc123",
    "tool_use_id": "toolu_abc123",
    "status": "completed",
    "output_file": "/tmp/task_abc123_output.json",
    "summary": "Analysis complete: found 3 issues",
    "usage": {
      "total_tokens": 5000,
      "tool_uses": 12,
      "duration_ms": 15000
    },
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :subtype, :session_id, :task_id]
  defstruct [
    :type,
    :subtype,
    :task_id,
    :tool_use_id,
    :status,
    :output_file,
    :summary,
    :usage,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :task_notification,
          task_id: String.t(),
          tool_use_id: String.t() | nil,
          status: :completed | :failed | :stopped,
          output_file: String.t() | nil,
          summary: String.t() | nil,
          usage: map() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new TaskNotificationMessage from JSON data.

  The `"status"` string is parsed to an atom (`:completed`, `:failed`, or `:stopped`).

  ## Examples

      iex> TaskNotificationMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "task_notification",
      ...>   "task_id" => "task_abc",
      ...>   "status" => "completed",
      ...>   "output_file" => "/tmp/output.json",
      ...>   "summary" => "Done",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %TaskNotificationMessage{type: :system, subtype: :task_notification, status: :completed, ...}}

      iex> TaskNotificationMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{"type" => "system", "subtype" => "task_notification", "task_id" => task_id, "session_id" => session_id} = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :task_notification,
       task_id: task_id,
       tool_use_id: json["tool_use_id"],
       status: parse_status(json["status"]),
       output_file: json["output_file"],
       summary: json["summary"],
       usage: json["usage"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "task_notification"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a TaskNotificationMessage.
  """
  @spec task_notification_message?(any()) :: boolean()
  def task_notification_message?(%__MODULE__{type: :system, subtype: :task_notification}), do: true
  def task_notification_message?(_), do: false

  defp parse_status("completed"), do: :completed
  defp parse_status("failed"), do: :failed
  defp parse_status("stopped"), do: :stopped
  defp parse_status(_), do: nil
end

defimpl Jason.Encoder, for: ClaudeCode.Message.TaskNotificationMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.TaskNotificationMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
