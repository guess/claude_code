defmodule ClaudeCode.Message.ToolUseSummaryMessage do
  @moduledoc """
  Represents a tool use summary message from the Claude CLI.

  Emitted as a summary of tool usage in a conversation, providing a
  human-readable description of what one or more tools did.

  ## Fields

  - `:summary` - Human-readable summary of the tool usage
  - `:preceding_tool_use_ids` - List of tool use IDs this summary covers
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "tool_use_summary",
    "summary": "Read 3 files and edited 1 file",
    "preceding_tool_use_ids": ["toolu_abc", "toolu_def"],
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :summary, :session_id]
  defstruct [
    :type,
    :summary,
    :uuid,
    :session_id,
    preceding_tool_use_ids: []
  ]

  @type t :: %__MODULE__{
          type: :tool_use_summary,
          summary: String.t(),
          preceding_tool_use_ids: [String.t()],
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new ToolUseSummaryMessage from JSON data.

  ## Examples

      iex> ToolUseSummaryMessage.new(%{
      ...>   "type" => "tool_use_summary",
      ...>   "summary" => "Read 3 files",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %ToolUseSummaryMessage{type: :tool_use_summary, ...}}

      iex> ToolUseSummaryMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "tool_use_summary", "summary" => summary, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :tool_use_summary,
       summary: summary,
       preceding_tool_use_ids: json["preceding_tool_use_ids"] || [],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "tool_use_summary"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a ToolUseSummaryMessage.
  """
  @spec tool_use_summary_message?(any()) :: boolean()
  def tool_use_summary_message?(%__MODULE__{type: :tool_use_summary}), do: true
  def tool_use_summary_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.ToolUseSummaryMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.ToolUseSummaryMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
