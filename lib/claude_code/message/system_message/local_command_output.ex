defmodule ClaudeCode.Message.SystemMessage.LocalCommandOutput do
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

  use ClaudeCode.JSONEncoder

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
  Creates a new LocalCommandOutput from JSON data.

  ## Examples

      iex> LocalCommandOutput.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "local_command_output",
      ...>   "content" => "output text",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %LocalCommandOutput{type: :system, subtype: :local_command_output, ...}}

      iex> LocalCommandOutput.new(%{"type" => "assistant"})
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
  Type guard to check if a value is a LocalCommandOutput.
  """
  @spec local_command_output?(any()) :: boolean()
  def local_command_output?(%__MODULE__{type: :system, subtype: :local_command_output}), do: true
  def local_command_output?(_), do: false
end
