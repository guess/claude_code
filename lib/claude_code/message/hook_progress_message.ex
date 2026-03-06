defmodule ClaudeCode.Message.HookProgressMessage do
  @moduledoc """
  Represents a hook progress system message from the Claude CLI.

  Emitted periodically while a hook is executing to relay intermediate output.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:hook_progress`
  - `:session_id` - Session identifier
  - `:uuid` - Message UUID
  - `:hook_id` - Unique identifier for this hook execution
  - `:hook_name` - Name of the hook being executed
  - `:hook_event` - Event that triggered the hook
  - `:stdout` - Standard output from the hook process
  - `:stderr` - Standard error from the hook process
  - `:output` - Combined or processed output

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "hook_progress",
    "session_id": "...",
    "uuid": "...",
    "hook_id": "hook_abc123",
    "hook_name": "my_hook",
    "hook_event": "on_tool_start",
    "stdout": "processing...",
    "stderr": null,
    "output": "processing..."
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
    :hook_event,
    :stdout,
    :stderr,
    :output
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :hook_progress,
          uuid: String.t() | nil,
          session_id: String.t(),
          hook_id: String.t(),
          hook_name: String.t(),
          hook_event: String.t(),
          stdout: String.t() | nil,
          stderr: String.t() | nil,
          output: String.t() | nil
        }

  @doc """
  Creates a new HookProgressMessage from JSON data.

  ## Examples

      iex> HookProgressMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "hook_progress",
      ...>   "session_id" => "session-1",
      ...>   "hook_id" => "hook_abc",
      ...>   "hook_name" => "my_hook",
      ...>   "hook_event" => "on_tool_start"
      ...> })
      {:ok, %HookProgressMessage{type: :system, subtype: :hook_progress, ...}}

      iex> HookProgressMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{
          "type" => "system",
          "subtype" => "hook_progress",
          "session_id" => session_id,
          "hook_id" => hook_id,
          "hook_name" => hook_name,
          "hook_event" => hook_event
        } = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :hook_progress,
       uuid: json["uuid"],
       session_id: session_id,
       hook_id: hook_id,
       hook_name: hook_name,
       hook_event: hook_event,
       stdout: json["stdout"],
       stderr: json["stderr"],
       output: json["output"]
     }}
  end

  def new(%{"type" => "system", "subtype" => "hook_progress"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a HookProgressMessage.
  """
  @spec hook_progress_message?(any()) :: boolean()
  def hook_progress_message?(%__MODULE__{type: :system, subtype: :hook_progress}), do: true
  def hook_progress_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.HookProgressMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.HookProgressMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
