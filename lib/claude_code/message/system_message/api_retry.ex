defmodule ClaudeCode.Message.SystemMessage.ApiRetry do
  @moduledoc """
  Represents an API retry notification from the Claude CLI.

  Emitted when the CLI is retrying an API request due to rate limits,
  server errors, or other transient failures.

  ## Fields

  - `:attempt` - The current retry attempt number (1-based)
  - `:max_retries` - Maximum number of retries that will be attempted
  - `:retry_delay_ms` - Delay in milliseconds before the next retry
  - `:error_status` - HTTP status code of the error (nil for connection errors)
  - `:error` - The error type atom
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## Error Types

  - `:authentication_failed` - Authentication error
  - `:billing_error` - Billing/payment error
  - `:rate_limit` - Rate limit exceeded
  - `:invalid_request` - Invalid request error
  - `:server_error` - Server-side error
  - `:unknown` - Unknown error
  - `:max_output_tokens` - Maximum output tokens exceeded

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "api_retry",
    "attempt": 1,
    "max_retries": 3,
    "retry_delay_ms": 5000,
    "error_status": 429,
    "error": "rate_limit",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :attempt, :max_retries, :retry_delay_ms, :error]
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
          error: atom(),
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new ApiRetry from JSON data.

  ## Examples

      iex> ApiRetry.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "api_retry",
      ...>   "attempt" => 1,
      ...>   "max_retries" => 3,
      ...>   "retry_delay_ms" => 5000,
      ...>   "error_status" => 429,
      ...>   "error" => "rate_limit",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %ApiRetry{type: :system, subtype: :api_retry, ...}}

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
          "error" => error,
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
       error: String.to_atom(error),
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
