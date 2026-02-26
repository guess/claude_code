defmodule ClaudeCode.Message.AuthStatusMessage do
  @moduledoc """
  Represents an authentication status message from the Claude CLI.

  Emitted during authentication flows, such as when the CLI is
  authenticating with the API or handling OAuth flows.

  ## Fields

  - `:is_authenticating` - Whether authentication is in progress
  - `:output` - List of output strings from the auth process
  - `:error` - Error message if authentication failed (optional)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "auth_status",
    "isAuthenticating": true,
    "output": ["Authenticating..."],
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :is_authenticating, :session_id]
  defstruct [
    :type,
    :is_authenticating,
    :error,
    :uuid,
    :session_id,
    output: []
  ]

  @type t :: %__MODULE__{
          type: :auth_status,
          is_authenticating: boolean(),
          output: [String.t()],
          error: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new AuthStatusMessage from JSON data.

  ## Examples

      iex> AuthStatusMessage.new(%{
      ...>   "type" => "auth_status",
      ...>   "isAuthenticating" => true,
      ...>   "output" => ["Authenticating..."],
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %AuthStatusMessage{type: :auth_status, ...}}

      iex> AuthStatusMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "auth_status", "isAuthenticating" => is_authenticating, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :auth_status,
       is_authenticating: is_authenticating,
       output: json["output"] || [],
       error: json["error"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "auth_status"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is an AuthStatusMessage.
  """
  @spec auth_status_message?(any()) :: boolean()
  def auth_status_message?(%__MODULE__{type: :auth_status}), do: true
  def auth_status_message?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Message.AuthStatusMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.AuthStatusMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
