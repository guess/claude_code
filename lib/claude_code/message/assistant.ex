defmodule ClaudeCode.Message.Assistant do
  @moduledoc """
  Represents an assistant message from the Claude CLI.

  Assistant messages contain Claude's responses, which can include text,
  tool use requests, or a combination of both.

  Matches the official SDK schema:
  ```
  {
    type: "assistant",
    message: { ... },  # Anthropic SDK Message type
    session_id: string
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
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :assistant,
          message: Types.message(),
          session_id: String.t()
        }

  @doc """
  Creates a new Assistant message from JSON data.

  ## Examples

      iex> Assistant.new(%{"type" => "assistant", "message" => %{...}})
      {:ok, %Assistant{...}}

      iex> Assistant.new(%{"type" => "user"})
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
  Type guard to check if a value is an Assistant message.
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
            usage: parse_usage(message_data["usage"])
          },
          session_id: parent_json["session_id"]
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
      cache_read_input_tokens: usage_data["cache_read_input_tokens"]
    }
  end

  defp parse_usage(_) do
    %{
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: nil,
      cache_read_input_tokens: nil
    }
  end
end
