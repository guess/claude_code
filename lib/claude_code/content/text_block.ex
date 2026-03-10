defmodule ClaudeCode.Content.TextBlock do
  @moduledoc """
  Represents a text content block within a Claude message.

  Text blocks contain plain text content that represents Claude's response
  or user input.
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :text]
  defstruct [:type, :text, :citations]

  @type t :: %__MODULE__{
          type: :text,
          text: String.t(),
          citations: [map()] | nil
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
        citations = parse_citations(data["citations"])
        {:ok, %__MODULE__{type: :text, text: text, citations: citations}}

      %{"text" => _} ->
        {:error, :invalid_text}

      _ ->
        {:error, :missing_text}
    end
  end

  def new(_), do: {:error, :invalid_content_type}

  defp parse_citations(nil), do: nil
  defp parse_citations(citations) when is_list(citations), do: citations
  defp parse_citations(_), do: nil
end

defimpl String.Chars, for: ClaudeCode.Content.TextBlock do
  def to_string(%{text: text}), do: text
end
