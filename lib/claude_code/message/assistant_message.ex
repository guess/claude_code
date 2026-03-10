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
            | "invalid_request" | "server_error" | "max_output_tokens"
            | "unknown" | null
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Content
  alias ClaudeCode.Message

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
          | :max_output_tokens
          | :unknown
          | String.t()

  @type message :: %{
          id: String.t(),
          type: :message | String.t() | nil,
          role: Message.role(),
          content: [Content.t()],
          model: String.t(),
          stop_reason: ClaudeCode.StopReason.t() | nil,
          stop_sequence: String.t() | nil,
          usage: ClaudeCode.Usage.t(),
          context_management: map() | nil
        }

  @type t :: %__MODULE__{
          type: :assistant,
          message: message(),
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
  Parses the inner API message (BetaMessage) from a JSON map.

  Used by both `AssistantMessage.new/1` (full messages) and
  `PartialAssistantMessage` (message_start events) since both
  contain the same Anthropic API Message structure.
  """
  @spec parse_api_message(map()) :: {:ok, message()} | {:error, term()}
  def parse_api_message(data) when is_map(data) do
    case Parser.parse_contents(data["content"] || []) do
      {:ok, content} ->
        {:ok,
         %{
           id: data["id"],
           type: parse_message_type(data["type"]),
           role: Message.parse_role(data["role"]),
           content: content,
           model: data["model"],
           stop_reason: ClaudeCode.StopReason.parse(data["stop_reason"]),
           stop_sequence: data["stop_sequence"],
           usage: ClaudeCode.Usage.parse(data["usage"]),
           context_management: data["context_management"]
         }}

      {:error, error} ->
        {:error, {:content_parse_error, error}}
    end
  end

  defp parse_message(message_data, parent_json) do
    with {:ok, message} <- parse_api_message(message_data) do
      {:ok,
       %__MODULE__{
         type: :assistant,
         message: message,
         session_id: parent_json["session_id"],
         uuid: parent_json["uuid"],
         parent_tool_use_id: parent_json["parent_tool_use_id"],
         error: parse_error(parent_json["error"])
       }}
    end
  end

  defp parse_message_type("message"), do: :message
  defp parse_message_type(value) when is_binary(value), do: value
  defp parse_message_type(_), do: nil

  @error_mapping %{
    "authentication_failed" => :authentication_failed,
    "billing_error" => :billing_error,
    "rate_limit" => :rate_limit,
    "invalid_request" => :invalid_request,
    "server_error" => :server_error,
    "max_output_tokens" => :max_output_tokens,
    "unknown" => :unknown
  }

  defp parse_error(value) when is_binary(value), do: Map.get(@error_mapping, value, value)
  defp parse_error(_), do: nil
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
