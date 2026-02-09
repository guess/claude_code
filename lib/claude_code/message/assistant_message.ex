defmodule ClaudeCode.Message.AssistantMessage do
  @moduledoc """
  Represents an assistant message from the Claude CLI.

  Assistant messages contain Claude's responses, which can include text,
  tool use requests, or a combination of both.

  Matches the official SDK schema:
  ```
  {
    type: "assistant",
    uuid: string,
    message: { ... },  # Anthropic SDK Message type
    session_id: string,
    parent_tool_use_id?: string | null,
    error?: "authentication_failed" | "billing_error" | "rate_limit"
            | "invalid_request" | "server_error" | "unknown" | null
  }
  ```
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Types

  @enforce_keys [
    :type,
    :message,
    :session_id
  ]
  defstruct [
    :type,
    :message,
    :session_id,
    :uuid,
    :parent_tool_use_id,
    :error
  ]

  @type assistant_message_error ::
          :authentication_failed
          | :billing_error
          | :rate_limit
          | :invalid_request
          | :server_error
          | :unknown

  @type t :: %__MODULE__{
          type: :assistant,
          message: Types.message(),
          session_id: String.t(),
          uuid: String.t() | nil,
          parent_tool_use_id: String.t() | nil,
          error: assistant_message_error() | nil
        }

  @doc """
  Creates a new AssistantMessage from JSON data.

  ## Examples

      iex> AssistantMessage.new(%{"type" => "assistant", "message" => %{...}})
      {:ok, %AssistantMessage{...}}

      iex> AssistantMessage.new(%{"type" => "user"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | tuple()}
  def new(%{"type" => "assistant"} = json) do
    case json do
      %{"message" => message_data} ->
        parse_message(message_data, json)

      _ ->
        {:error, :missing_message}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is an AssistantMessage.
  """
  @spec assistant_message?(any()) :: boolean()
  def assistant_message?(%__MODULE__{type: :assistant}), do: true
  def assistant_message?(_), do: false

  defp parse_message(message_data, parent_json) do
    case Content.parse_all(message_data["content"] || []) do
      {:ok, content} ->
        message_struct = %__MODULE__{
          type: :assistant,
          message: %{
            id: message_data["id"],
            type: :message,
            role: :assistant,
            content: content,
            model: message_data["model"],
            stop_reason: parse_stop_reason(message_data["stop_reason"]),
            stop_sequence: message_data["stop_sequence"],
            usage: parse_usage(message_data["usage"]),
            context_management: message_data["context_management"]
          },
          session_id: parent_json["session_id"],
          uuid: parent_json["uuid"],
          parent_tool_use_id: parent_json["parent_tool_use_id"],
          error: parse_error(parent_json["error"])
        }

        {:ok, message_struct}

      {:error, error} ->
        {:error, {:content_parse_error, error}}
    end
  end

  defp parse_stop_reason(nil), do: nil
  defp parse_stop_reason("end_turn"), do: :end_turn
  defp parse_stop_reason("max_tokens"), do: :max_tokens
  defp parse_stop_reason("stop_sequence"), do: :stop_sequence
  defp parse_stop_reason("tool_use"), do: :tool_use
  defp parse_stop_reason(other) when is_binary(other), do: String.to_atom(other)

  defp parse_usage(usage_data) when is_map(usage_data) do
    %{
      input_tokens: usage_data["input_tokens"] || 0,
      output_tokens: usage_data["output_tokens"] || 0,
      cache_creation_input_tokens: usage_data["cache_creation_input_tokens"],
      cache_read_input_tokens: usage_data["cache_read_input_tokens"],
      cache_creation: parse_cache_creation(usage_data["cache_creation"]),
      service_tier: usage_data["service_tier"],
      inference_geo: usage_data["inference_geo"]
    }
  end

  defp parse_usage(_) do
    %{
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: nil,
      cache_read_input_tokens: nil,
      cache_creation: nil,
      service_tier: nil,
      inference_geo: nil
    }
  end

  defp parse_cache_creation(%{"ephemeral_5m_input_tokens" => t5m, "ephemeral_1h_input_tokens" => t1h}) do
    %{ephemeral_5m_input_tokens: t5m, ephemeral_1h_input_tokens: t1h}
  end

  defp parse_cache_creation(_), do: nil

  defp parse_error(nil), do: nil
  defp parse_error("authentication_failed"), do: :authentication_failed
  defp parse_error("billing_error"), do: :billing_error
  defp parse_error("rate_limit"), do: :rate_limit
  defp parse_error("invalid_request"), do: :invalid_request
  defp parse_error("server_error"), do: :server_error
  defp parse_error("unknown"), do: :unknown
  defp parse_error(other) when is_binary(other), do: String.to_atom(other)
end

defimpl String.Chars, for: ClaudeCode.Message.AssistantMessage do
  alias ClaudeCode.Content.TextBlock

  def to_string(%{message: %{content: content}}) when is_list(content) do
    content
    |> Enum.filter(&match?(%TextBlock{}, &1))
    |> Enum.map_join(& &1.text)
  end

  def to_string(_), do: ""
end

defimpl Jason.Encoder, for: ClaudeCode.Message.AssistantMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.AssistantMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
