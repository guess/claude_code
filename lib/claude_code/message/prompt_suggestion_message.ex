defmodule ClaudeCode.Message.PromptSuggestionMessage do
  @moduledoc """
  Represents a prompt suggestion message from the Claude CLI.

  Emitted after each turn when the `promptSuggestions` option is enabled.
  Contains a predicted next user prompt that can be shown as a suggestion
  in UI applications.

  ## Fields

  - `:suggestion` - The suggested next prompt
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "prompt_suggestion",
    "suggestion": "Now add tests for the new function",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :suggestion, :session_id]
  defstruct [
    :type,
    :suggestion,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :prompt_suggestion,
          suggestion: String.t(),
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new PromptSuggestionMessage from JSON data.

  ## Examples

      iex> PromptSuggestionMessage.new(%{
      ...>   "type" => "prompt_suggestion",
      ...>   "suggestion" => "Add tests for the new module",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %PromptSuggestionMessage{type: :prompt_suggestion, ...}}

      iex> PromptSuggestionMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "prompt_suggestion", "suggestion" => suggestion, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :prompt_suggestion,
       suggestion: suggestion,
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "prompt_suggestion"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}
end
