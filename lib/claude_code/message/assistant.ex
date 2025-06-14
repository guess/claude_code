defmodule ClaudeCode.Message.Assistant do
  @moduledoc """
  Represents an assistant message from the Claude CLI.
  
  Assistant messages contain Claude's responses, which can include text,
  tool use requests, or a combination of both.
  """
  
  alias ClaudeCode.Content
  
  @enforce_keys [:type, :message_id, :role, :model, :content, :stop_reason,
                 :stop_sequence, :usage, :parent_tool_use_id, :session_id]
  defstruct [
    :type,
    :message_id,
    :role,
    :model,
    :content,
    :stop_reason,
    :stop_sequence,
    :usage,
    :parent_tool_use_id,
    :session_id
  ]
  
  @type t :: %__MODULE__{
    type: :assistant,
    message_id: String.t(),
    role: :assistant,
    model: String.t(),
    content: [Content.t()],
    stop_reason: nil | :tool_use | :end_turn | atom(),
    stop_sequence: nil | String.t(),
    usage: usage_stats(),
    parent_tool_use_id: nil | String.t(),
    session_id: String.t()
  }
  
  @type usage_stats :: %{
    input_tokens: integer(),
    cache_creation_input_tokens: integer(),
    cache_read_input_tokens: integer(),
    output_tokens: integer(),
    service_tier: String.t()
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
  @spec is_assistant_message?(any()) :: boolean()
  def is_assistant_message?(%__MODULE__{type: :assistant}), do: true
  def is_assistant_message?(_), do: false
  
  defp parse_message(message_data, parent_json) do
    with {:ok, content} <- Content.parse_all(message_data["content"] || []) do
      message = %__MODULE__{
        type: :assistant,
        message_id: message_data["id"],
        role: :assistant,
        model: message_data["model"],
        content: content,
        stop_reason: parse_stop_reason(message_data["stop_reason"]),
        stop_sequence: message_data["stop_sequence"],
        usage: parse_usage(message_data["usage"]),
        parent_tool_use_id: parent_json["parent_tool_use_id"],
        session_id: parent_json["session_id"]
      }
      
      {:ok, message}
    else
      {:error, error} -> {:error, {:content_parse_error, error}}
    end
  end
  
  defp parse_stop_reason(nil), do: nil
  defp parse_stop_reason("tool_use"), do: :tool_use
  defp parse_stop_reason("end_turn"), do: :end_turn
  defp parse_stop_reason(other) when is_binary(other), do: String.to_atom(other)
  
  defp parse_usage(usage_data) when is_map(usage_data) do
    %{
      input_tokens: usage_data["input_tokens"] || 0,
      cache_creation_input_tokens: usage_data["cache_creation_input_tokens"] || 0,
      cache_read_input_tokens: usage_data["cache_read_input_tokens"] || 0,
      output_tokens: usage_data["output_tokens"] || 0,
      service_tier: usage_data["service_tier"] || "standard"
    }
  end
  
  defp parse_usage(_), do: %{
    input_tokens: 0,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    output_tokens: 0,
    service_tier: "standard"
  }
end