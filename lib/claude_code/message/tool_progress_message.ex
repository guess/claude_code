defmodule ClaudeCode.Message.ToolProgressMessage do
  @moduledoc """
  Represents a tool progress message from the Claude CLI.

  Emitted periodically while a tool is executing to indicate progress.
  Useful for showing elapsed time or progress indicators in UIs.

  ## Fields

  - `:tool_use_id` - The tool use block ID
  - `:tool_name` - Name of the executing tool
  - `:parent_tool_use_id` - Parent tool use ID if in a subagent context
  - `:elapsed_time_seconds` - Seconds since the tool started
  - `:task_id` - Background task ID (optional)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "tool_progress",
    "tool_use_id": "toolu_abc123",
    "tool_name": "Bash",
    "parent_tool_use_id": null,
    "elapsed_time_seconds": 5.2,
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :tool_use_id, :tool_name, :session_id]
  defstruct [
    :type,
    :tool_use_id,
    :tool_name,
    :parent_tool_use_id,
    :elapsed_time_seconds,
    :task_id,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :tool_progress,
          tool_use_id: String.t(),
          tool_name: String.t(),
          parent_tool_use_id: String.t() | nil,
          elapsed_time_seconds: number() | nil,
          task_id: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new ToolProgressMessage from JSON data.

  ## Examples

      iex> ToolProgressMessage.new(%{
      ...>   "type" => "tool_progress",
      ...>   "tool_use_id" => "toolu_abc",
      ...>   "tool_name" => "Bash",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %ToolProgressMessage{type: :tool_progress, ...}}

      iex> ToolProgressMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{"type" => "tool_progress", "tool_use_id" => tool_use_id, "tool_name" => tool_name, "session_id" => session_id} =
          json
      ) do
    {:ok,
     %__MODULE__{
       type: :tool_progress,
       tool_use_id: tool_use_id,
       tool_name: tool_name,
       parent_tool_use_id: json["parent_tool_use_id"],
       elapsed_time_seconds: json["elapsed_time_seconds"],
       task_id: json["task_id"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "tool_progress"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a ToolProgressMessage.
  """
  @spec tool_progress_message?(any()) :: boolean()
  def tool_progress_message?(%__MODULE__{type: :tool_progress}), do: true
  def tool_progress_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.ToolProgressMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.ToolProgressMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
