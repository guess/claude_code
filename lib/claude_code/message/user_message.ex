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
    tool_use_result?: object | null  # Rich metadata about the tool result
  }
  ```
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Types

  @enforce_keys [:type, :message, :session_id]
  defstruct [
    :type,
    :message,
    :session_id,
    :uuid,
    :parent_tool_use_id,
    :tool_use_result
  ]

  @type t :: %__MODULE__{
          type: :user,
          message: Types.message_param(),
          session_id: Types.session_id(),
          uuid: String.t() | nil,
          parent_tool_use_id: String.t() | nil,
          tool_use_result: map() | nil
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

  @doc """
  Type guard to check if a value is a UserMessage.
  """
  @spec user_message?(any()) :: boolean()
  def user_message?(%__MODULE__{type: :user}), do: true
  def user_message?(_), do: false

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
          tool_use_result: parent_json["tool_use_result"]
        }

        {:ok, message_struct}

      {:error, error} ->
        {:error, {:content_parse_error, error}}
    end
  end

  defp parse_content(content) when is_binary(content), do: {:ok, content}
  defp parse_content(content) when is_list(content), do: Content.parse_all(content)
  defp parse_content(_), do: {:ok, []}
end

defimpl Jason.Encoder, for: ClaudeCode.Message.UserMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.UserMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
