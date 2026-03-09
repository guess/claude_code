defmodule ClaudeCode.Message.TaskProgressMessage do
  @moduledoc """
  Represents a task progress system message from the Claude CLI.

  Emitted periodically while a background task is executing to indicate progress.
  Useful for showing elapsed time, token usage, or tool activity in UIs.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:task_progress`
  - `:task_id` - Unique identifier for the task
  - `:tool_use_id` - Associated tool use block ID (optional)
  - `:description` - Human-readable progress description
  - `:usage` - Token and tool usage stats (optional map with `total_tokens`, `tool_uses`, `duration_ms`)
  - `:last_tool_name` - Name of the most recently used tool (optional)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "task_progress",
    "task_id": "task_abc123",
    "tool_use_id": "toolu_abc123",
    "description": "Analyzing files...",
    "usage": {
      "total_tokens": 1500,
      "tool_uses": 3,
      "duration_ms": 4200
    },
    "last_tool_name": "Read",
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
    :description,
    :usage,
    :last_tool_name,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :task_progress,
          task_id: String.t(),
          tool_use_id: String.t() | nil,
          description: String.t() | nil,
          usage: map() | nil,
          last_tool_name: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new TaskProgressMessage from JSON data.

  ## Examples

      iex> TaskProgressMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "task_progress",
      ...>   "task_id" => "task_abc",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %TaskProgressMessage{type: :system, subtype: :task_progress, ...}}

      iex> TaskProgressMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "task_progress", "task_id" => task_id, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :task_progress,
       task_id: task_id,
       tool_use_id: json["tool_use_id"],
       description: json["description"],
       usage: json["usage"],
       last_tool_name: json["last_tool_name"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "task_progress"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a TaskProgressMessage.
  """
  @spec task_progress_message?(any()) :: boolean()
  def task_progress_message?(%__MODULE__{type: :system, subtype: :task_progress}), do: true
  def task_progress_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.TaskProgressMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.TaskProgressMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
