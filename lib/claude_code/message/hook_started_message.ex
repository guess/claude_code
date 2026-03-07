defmodule ClaudeCode.Message.HookStartedMessage do
  @moduledoc """
  Represents a hook started system message from the Claude CLI.

  Emitted when a hook begins execution.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:hook_started`
  - `:session_id` - Session identifier
  - `:uuid` - Message UUID
  - `:hook_id` - Unique identifier for this hook execution
  - `:hook_name` - Name of the hook being executed
  - `:hook_event` - Event that triggered the hook

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "hook_started",
    "session_id": "...",
    "uuid": "...",
    "hook_id": "hook_abc123",
    "hook_name": "my_hook",
    "hook_event": "on_tool_start"
  }
  ```
  """

  @enforce_keys [:type, :subtype, :session_id, :hook_id, :hook_name, :hook_event]
  defstruct [
    :type,
    :subtype,
    :uuid,
    :session_id,
    :hook_id,
    :hook_name,
    :hook_event
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :hook_started,
          uuid: String.t() | nil,
          session_id: String.t(),
          hook_id: String.t(),
          hook_name: String.t(),
          hook_event: String.t()
        }

  @doc """
  Creates a new HookStartedMessage from JSON data.

  ## Examples

      iex> HookStartedMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "hook_started",
      ...>   "session_id" => "session-1",
      ...>   "hook_id" => "hook_abc",
      ...>   "hook_name" => "my_hook",
      ...>   "hook_event" => "on_tool_start"
      ...> })
      {:ok, %HookStartedMessage{type: :system, subtype: :hook_started, ...}}

      iex> HookStartedMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{
          "type" => "system",
          "subtype" => "hook_started",
          "session_id" => session_id,
          "hook_id" => hook_id,
          "hook_name" => hook_name,
          "hook_event" => hook_event
        } = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :hook_started,
       uuid: json["uuid"],
       session_id: session_id,
       hook_id: hook_id,
       hook_name: hook_name,
       hook_event: hook_event
     }}
  end

  def new(%{"type" => "system", "subtype" => "hook_started"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a HookStartedMessage.
  """
  @spec hook_started_message?(any()) :: boolean()
  def hook_started_message?(%__MODULE__{type: :system, subtype: :hook_started}), do: true
  def hook_started_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.HookStartedMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.HookStartedMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
