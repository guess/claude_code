defmodule ClaudeCode.Message.LocalCommandOutputMessage do
  @moduledoc """
  Represents a local command output message from the Claude CLI.

  Emitted when the CLI produces output from a local command execution.

  ## Fields

  - `:content` - The command output content string
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "local_command_output",
    "content": "command output here",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :subtype, :session_id, :content]
  defstruct [
    :type,
    :subtype,
    :content,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :local_command_output,
          content: String.t(),
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new LocalCommandOutputMessage from JSON data.

  ## Examples

      iex> LocalCommandOutputMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "local_command_output",
      ...>   "content" => "output text",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %LocalCommandOutputMessage{type: :system, subtype: :local_command_output, ...}}

      iex> LocalCommandOutputMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{"type" => "system", "subtype" => "local_command_output", "content" => content, "session_id" => session_id} =
          json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :local_command_output,
       content: content,
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "local_command_output"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a LocalCommandOutputMessage.
  """
  @spec local_command_output_message?(any()) :: boolean()
  def local_command_output_message?(%__MODULE__{type: :system, subtype: :local_command_output}), do: true
  def local_command_output_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.LocalCommandOutputMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.LocalCommandOutputMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
