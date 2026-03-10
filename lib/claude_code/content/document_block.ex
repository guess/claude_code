defmodule ClaudeCode.Content.DocumentBlock do
  @moduledoc """
  Represents a document content block within a Claude message.

  Document blocks contain document data (PDF, plain text) either inline or by
  reference. They appear in user messages and can also appear within server tool
  results (e.g., web fetch).

  ## Source types

    * `"base64"` — inline document with `data` and `media_type`
    * `"text"` — inline plain text with `data` and `media_type`
    * `"url"` — remote document referenced by `url`
    * `"content"` — structured content with nested blocks
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :source]
  defstruct [:type, :source, :title, :context, :citations]

  @type source ::
          %{
            type: :base64,
            media_type: String.t(),
            data: String.t()
          }
          | %{
              type: :text,
              media_type: String.t(),
              data: String.t()
            }
          | %{
              type: :url,
              url: String.t()
            }
          | %{
              type: :content,
              content: list() | String.t()
            }

  @type t :: %__MODULE__{
          type: :document,
          source: source(),
          title: String.t() | nil,
          context: String.t() | nil,
          citations: map() | nil
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "document", "source" => source} = data) when is_map(source) do
    case parse_source(source) do
      {:ok, parsed_source} ->
        {:ok,
         %__MODULE__{
           type: :document,
           source: parsed_source,
           title: data["title"],
           context: data["context"],
           citations: data["citations"]
         }}

      error ->
        error
    end
  end

  def new(%{"type" => "document"}), do: {:error, {:missing_fields, [:source]}}
  def new(_), do: {:error, :invalid_content_type}

  defp parse_source(%{"type" => type, "data" => data, "media_type" => media_type}) when type in ["base64", "text"],
    do: {:ok, %{type: String.to_atom(type), media_type: media_type, data: data}}

  defp parse_source(%{"type" => type} = s) when type in ["base64", "text"],
    do: {:error, {:missing_fields, missing_keys(s, ["data", "media_type"])}}

  defp parse_source(%{"type" => "url", "url" => url}) when is_binary(url), do: {:ok, %{type: :url, url: url}}

  defp parse_source(%{"type" => "url"}), do: {:error, {:missing_fields, [:url]}}

  defp parse_source(%{"type" => "content", "content" => content}), do: {:ok, %{type: :content, content: content}}

  defp parse_source(%{"type" => "content"}), do: {:error, {:missing_fields, [:content]}}
  defp parse_source(%{"type" => _}), do: {:error, :unknown_source_type}
  defp parse_source(_), do: {:error, {:missing_fields, [:type]}}

  defp missing_keys(map, keys), do: for(k <- keys, not Map.has_key?(map, k), do: String.to_atom(k))
end

defimpl String.Chars, for: ClaudeCode.Content.DocumentBlock do
  def to_string(%{title: title}) when is_binary(title), do: "[document: #{title}]"
  def to_string(%{source: %{type: type}}), do: "[document: #{type}]"
end
