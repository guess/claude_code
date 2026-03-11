defmodule ClaudeCode.Message.SystemMessage.TaskProgress do
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
  - `:summary` - AI-generated summary of progress so far (optional)
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

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :task_id]
  defstruct [
    :type,
    :subtype,
    :task_id,
    :tool_use_id,
    :description,
    :usage,
    :last_tool_name,
    :summary,
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
          summary: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new TaskProgress from JSON data.

  ## Examples

      iex> TaskProgress.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "task_progress",
      ...>   "task_id" => "task_abc",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %TaskProgress{type: :system, subtype: :task_progress, ...}}

      iex> TaskProgress.new(%{"type" => "assistant"})
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
       summary: json["summary"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "task_progress"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a TaskProgress.
  """
  @spec task_progress?(any()) :: boolean()
  def task_progress?(%__MODULE__{type: :system, subtype: :task_progress}), do: true
  def task_progress?(_), do: false
end
