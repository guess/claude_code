defmodule ClaudeCode.Message.SystemMessage.TaskStarted do
  @moduledoc """
  Represents a task started system message from the Claude CLI.

  Emitted when a background task begins execution.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:task_started`
  - `:task_id` - Unique identifier for the task
  - `:tool_use_id` - Associated tool use block ID (optional)
  - `:description` - Human-readable description of the task
  - `:task_type` - Type classification of the task (optional)
  - `:prompt` - The prompt or instruction that started the task (optional)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "task_started",
    "task_id": "task_abc123",
    "tool_use_id": "toolu_abc123",
    "description": "Running background analysis",
    "task_type": "background",
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
    :task_type,
    :prompt,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :task_started,
          task_id: String.t(),
          tool_use_id: String.t() | nil,
          description: String.t() | nil,
          task_type: String.t() | nil,
          prompt: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new TaskStarted from JSON data.

  ## Examples

      iex> TaskStarted.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "task_started",
      ...>   "task_id" => "task_abc",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %TaskStarted{type: :system, subtype: :task_started, ...}}

      iex> TaskStarted.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "task_started", "task_id" => task_id, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :task_started,
       task_id: task_id,
       tool_use_id: json["tool_use_id"],
       description: json["description"],
       task_type: json["task_type"],
       prompt: json["prompt"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "task_started"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a TaskStarted.
  """
  @spec task_started?(any()) :: boolean()
  def task_started?(%__MODULE__{type: :system, subtype: :task_started}), do: true
  def task_started?(_), do: false
end
