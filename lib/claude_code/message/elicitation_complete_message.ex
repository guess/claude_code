defmodule ClaudeCode.Message.ElicitationCompleteMessage do
  @moduledoc """
  Represents an elicitation complete message from the Claude CLI.

  Emitted when an MCP server elicitation flow has completed.

  ## Fields

  - `:mcp_server_name` - Name of the MCP server that completed elicitation
  - `:elicitation_id` - Unique identifier for the elicitation
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "elicitation_complete",
    "mcp_server_name": "server-name",
    "elicitation_id": "elicit-abc123",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :subtype, :session_id, :mcp_server_name, :elicitation_id]
  defstruct [
    :type,
    :subtype,
    :mcp_server_name,
    :elicitation_id,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :elicitation_complete,
          mcp_server_name: String.t(),
          elicitation_id: String.t(),
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new ElicitationCompleteMessage from JSON data.

  ## Examples

      iex> ElicitationCompleteMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "elicitation_complete",
      ...>   "mcp_server_name" => "my-server",
      ...>   "elicitation_id" => "elicit-1",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %ElicitationCompleteMessage{type: :system, subtype: :elicitation_complete, ...}}

      iex> ElicitationCompleteMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{
          "type" => "system",
          "subtype" => "elicitation_complete",
          "mcp_server_name" => mcp_server_name,
          "elicitation_id" => elicitation_id,
          "session_id" => session_id
        } = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :elicitation_complete,
       mcp_server_name: mcp_server_name,
       elicitation_id: elicitation_id,
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "elicitation_complete"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is an ElicitationCompleteMessage.
  """
  @spec elicitation_complete_message?(any()) :: boolean()
  def elicitation_complete_message?(%__MODULE__{type: :system, subtype: :elicitation_complete}), do: true
  def elicitation_complete_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.ElicitationCompleteMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.ElicitationCompleteMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
