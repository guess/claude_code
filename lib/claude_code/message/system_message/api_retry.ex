defmodule ClaudeCode.Message.SystemMessage.ApiRetry do
  @moduledoc """
  Represents an API retry system message from the Claude CLI.

  Emitted when the CLI retries an API request after a transient error,
  containing retry metadata and the error that triggered the retry.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:api_retry`
  - `:attempt` - The current retry attempt number
  - `:max_retries` - Maximum number of retries allowed
  - `:retry_delay_ms` - Delay in milliseconds before the next retry
  - `:error_status` - HTTP status code of the error (nullable integer)
  - `:error` - The error object as a raw map (SDKAssistantMessageError shape)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "api_retry",
    "attempt": 1,
    "max_retries": 3,
    "retry_delay_ms": 1000,
    "error_status": 429,
    "error": {"type": "error", "error": {"type": "rate_limit_error", "message": "..."}},
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :attempt, :max_retries, :retry_delay_ms]
  defstruct [
    :type,
    :subtype,
    :attempt,
    :max_retries,
    :retry_delay_ms,
    :error_status,
    :error,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :api_retry,
          attempt: integer(),
          max_retries: integer(),
          retry_delay_ms: integer(),
          error_status: integer() | nil,
          error: map() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new ApiRetry from JSON data.

  The `"error"` object is stored as a raw map.

  ## Examples

      iex> ApiRetry.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "api_retry",
      ...>   "attempt" => 1,
      ...>   "max_retries" => 3,
      ...>   "retry_delay_ms" => 1000,
      ...>   "error_status" => 429,
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %ApiRetry{type: :system, subtype: :api_retry, attempt: 1, ...}}

      iex> ApiRetry.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(
        %{
          "type" => "system",
          "subtype" => "api_retry",
          "attempt" => attempt,
          "max_retries" => max_retries,
          "retry_delay_ms" => retry_delay_ms,
          "session_id" => session_id
        } = json
      ) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :api_retry,
       attempt: attempt,
       max_retries: max_retries,
       retry_delay_ms: retry_delay_ms,
       error_status: json["error_status"],
       error: json["error"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "api_retry"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is an ApiRetry.
  """
  @spec api_retry?(any()) :: boolean()
  def api_retry?(%__MODULE__{type: :system, subtype: :api_retry}), do: true
  def api_retry?(_), do: false
end
