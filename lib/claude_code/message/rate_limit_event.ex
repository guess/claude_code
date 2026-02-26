defmodule ClaudeCode.Message.RateLimitEvent do
  @moduledoc """
  Represents a rate limit event from the Claude CLI.

  Emitted when the session encounters a rate limit. This is common for
  claude.ai subscription users and provides information about rate limit
  status and when limits reset.

  ## Fields

  - `:rate_limit_info` - Map with rate limit details:
    - `:status` - One of `:allowed`, `:allowed_warning`, or `:rejected`
    - `:resets_at` - Unix timestamp (ms) when the limit resets (optional)
    - `:utilization` - Current utilization as a float 0.0–1.0 (optional)
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "rate_limit_event",
    "rate_limit_info": {
      "status": "allowed_warning",
      "resetsAt": 1700000000000,
      "utilization": 0.85
    },
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :rate_limit_info, :session_id]
  defstruct [
    :type,
    :rate_limit_info,
    :uuid,
    :session_id
  ]

  @type status :: :allowed | :allowed_warning | :rejected

  @type t :: %__MODULE__{
          type: :rate_limit_event,
          rate_limit_info: %{
            status: status(),
            resets_at: integer() | nil,
            utilization: number() | nil
          },
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new RateLimitEvent from JSON data.

  ## Examples

      iex> RateLimitEvent.new(%{
      ...>   "type" => "rate_limit_event",
      ...>   "rate_limit_info" => %{"status" => "allowed_warning", "resetsAt" => 1700000000000},
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %RateLimitEvent{type: :rate_limit_event, ...}}

      iex> RateLimitEvent.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "rate_limit_event", "rate_limit_info" => info, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :rate_limit_event,
       rate_limit_info: parse_rate_limit_info(info),
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "rate_limit_event"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a RateLimitEvent.
  """
  @spec rate_limit_event?(any()) :: boolean()
  def rate_limit_event?(%__MODULE__{type: :rate_limit_event}), do: true
  def rate_limit_event?(_), do: false

  defp parse_rate_limit_info(info) when is_map(info) do
    %{
      status: parse_status(info["status"]),
      resets_at: info["resetsAt"],
      utilization: info["utilization"]
    }
  end

  defp parse_status("allowed"), do: :allowed
  defp parse_status("allowed_warning"), do: :allowed_warning
  defp parse_status("rejected"), do: :rejected
  defp parse_status(other), do: other
end

defimpl Jason.Encoder, for: ClaudeCode.Message.RateLimitEvent do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.RateLimitEvent do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
