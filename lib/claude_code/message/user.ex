defmodule ClaudeCode.Message.User do
  @moduledoc """
  Represents a user message from the Claude CLI.

  User messages typically contain tool results in response to Claude's
  tool use requests.

  Matches the official SDK schema:
  ```
  {
    type: "user",
    message: MessageParam,  # from Anthropic SDK
    session_id: string
  }
  ```
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Types

  @enforce_keys [:type, :message, :session_id]
  defstruct [
    :type,
    :message,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :user,
          message: Types.message_param(),
          session_id: Types.session_id()
        }

  @doc """
  Creates a new User message from JSON data.

  ## Examples

      iex> User.new(%{"type" => "user", "message" => %{...}})
      {:ok, %User{...}}

      iex> User.new(%{"type" => "assistant"})
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
  Type guard to check if a value is a User message.
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
          session_id: parent_json["session_id"]
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
