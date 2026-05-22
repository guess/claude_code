defmodule ClaudeCode.Message.SystemMessage.TaskUpdated do
  @moduledoc """
  Represents a task updated system message from the Claude CLI.

  Emitted when a background task has one or more fields updated,
  containing the task ID and a patch map with the changed fields.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:task_updated`
  - `:task_id` - Unique identifier for the task being updated
  - `:patch` - Map of updated fields (all optional: status, description, end_time, total_paused_ms, error, is_backgrounded)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "task_updated",
    "task_id": "task_abc123",
    "patch": {"status": "running", "is_backgrounded": true},
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
    :patch,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :task_updated,
          task_id: String.t(),
          patch: map() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new TaskUpdated from JSON data.

  The `"patch"` map is stored as-is (raw map with all optional fields).

  ## Examples

      iex> TaskUpdated.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "task_updated",
      ...>   "task_id" => "task_abc123",
      ...>   "patch" => %{"status" => "running"},
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %TaskUpdated{type: :system, subtype: :task_updated, task_id: "task_abc123", ...}}

      iex> TaskUpdated.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "task_updated", "task_id" => task_id, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :task_updated,
       task_id: task_id,
       patch: json["patch"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "task_updated"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a TaskUpdated.
  """
  @spec task_updated?(any()) :: boolean()
  def task_updated?(%__MODULE__{type: :system, subtype: :task_updated}), do: true
  def task_updated?(_), do: false
end
