defmodule ClaudeCode.Content.TextBlock do
  @moduledoc """
  Represents a text content block within a Claude message.

  Text blocks contain plain text content that represents Claude's response
  or user input.
  """

  @enforce_keys [:type, :text]
  defstruct [:type, :text]

  @type t :: %__MODULE__{
          type: :text,
          text: String.t()
        }

  @doc """
  Creates a new Text content block from JSON data.

  ## Examples

      iex> Text.new(%{"type" => "text", "text" => "Hello!"})
      {:ok, %Text{type: :text, text: "Hello!"}}

      iex> Text.new(%{"type" => "tool_use", "text" => "Hi"})
      {:error, :invalid_content_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "text"} = data) do
    case data do
      %{"text" => text} when is_binary(text) ->
        {:ok, %__MODULE__{type: :text, text: text}}

      %{"text" => _} ->
        {:error, :invalid_text}

      _ ->
        {:error, :missing_text}
    end
  end

  def new(_), do: {:error, :invalid_content_type}

  @doc """
  Type guard to check if a value is a Text content block.
  """
  @spec text_content?(any()) :: boolean()
  def text_content?(%__MODULE__{type: :text}), do: true
  def text_content?(_), do: false
end

defimpl String.Chars, for: ClaudeCode.Content.TextBlock do
  def to_string(%{text: text}), do: text
end

defimpl Jason.Encoder, for: ClaudeCode.Content.TextBlock do
  def encode(block, opts) do
    block
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Content.TextBlock do
  def encode(block, encoder) do
    block
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
