defmodule ClaudeCode.Message.User do
  @moduledoc """
  Represents a user message from the Claude CLI.
  
  User messages typically contain tool results in response to Claude's
  tool use requests.
  """
  
  alias ClaudeCode.Content
  
  @enforce_keys [:type, :role, :content, :parent_tool_use_id, :session_id]
  defstruct [
    :type,
    :role,
    :content,
    :parent_tool_use_id,
    :session_id
  ]
  
  @type t :: %__MODULE__{
    type: :user,
    role: :user,
    content: [Content.t()],
    parent_tool_use_id: nil | String.t(),
    session_id: String.t()
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
  @spec is_user_message?(any()) :: boolean()
  def is_user_message?(%__MODULE__{type: :user}), do: true
  def is_user_message?(_), do: false
  
  defp parse_message(message_data, parent_json) do
    with {:ok, content} <- Content.parse_all(message_data["content"] || []) do
      message = %__MODULE__{
        type: :user,
        role: :user,
        content: content,
        parent_tool_use_id: parent_json["parent_tool_use_id"],
        session_id: parent_json["session_id"]
      }
      
      {:ok, message}
    else
      {:error, error} -> {:error, {:content_parse_error, error}}
    end
  end
end