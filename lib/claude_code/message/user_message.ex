defmodule ClaudeCode.Message.UserMessage do
  @moduledoc """
  Represents a user message from the Claude CLI.

  User messages typically contain tool results in response to Claude's
  tool use requests.

  Matches the official SDK schema:
  ```
  {
    type: "user",
    uuid?: string,
    message: MessageParam,  # from Anthropic SDK
    session_id: string,
    parent_tool_use_id?: string | null,
    tool_use_result?: object | null,  # Rich metadata about the tool result
    isSynthetic: boolean,             # Whether this is a synthetic message
    isReplay: boolean                 # Whether this is a replayed message
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Content
  alias ClaudeCode.Message

  @enforce_keys [:type, :message, :session_id]
  defstruct [
    :type,
    :message,
    :session_id,
    :uuid,
    :parent_tool_use_id,
    :tool_use_result,
    is_synthetic: false,
    is_replay: false
  ]

  @type message_content :: String.t() | [Content.t()]

  @type message_param :: %{
          content: message_content(),
          role: Message.role()
        }

  @type t :: %__MODULE__{
          type: :user,
          message: message_param(),
          session_id: String.t(),
          uuid: String.t() | nil,
          parent_tool_use_id: String.t() | nil,
          tool_use_result: map() | String.t() | nil,
          is_synthetic: boolean(),
          is_replay: boolean()
        }

  @doc """
  Creates a new UserMessage from JSON data.

  ## Examples

      iex> UserMessage.new(%{"type" => "user", "message" => %{...}})
      {:ok, %UserMessage{...}}

      iex> UserMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | tuple()}
  def new(%{"type" => "user"} = json) do
    case json do
      %{"message" => message_data} ->
        parse_message(message_data, json)

      _ ->
        {:error, :missing_message}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  defp parse_message(message_data, parent_json) do
    case parse_content(message_data["content"]) do
      {:ok, content} ->
        message_struct = %__MODULE__{
          type: :user,
          message: %{
            content: content,
            role: :user
          },
          session_id: parent_json["session_id"],
          uuid: parent_json["uuid"],
          parent_tool_use_id: parent_json["parent_tool_use_id"],
          tool_use_result: parent_json["tool_use_result"],
          is_synthetic: parent_json["is_synthetic"] || false,
          is_replay: parent_json["is_replay"] || false
        }

        {:ok, message_struct}

      {:error, error} ->
        {:error, {:content_parse_error, error}}
    end
  end

  defp parse_content(content) when is_binary(content), do: {:ok, content}
  defp parse_content(content) when is_list(content), do: Parser.parse_contents(content)
  defp parse_content(_), do: {:ok, []}
end
