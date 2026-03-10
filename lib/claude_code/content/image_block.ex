defmodule ClaudeCode.Content.ImageBlock do
  @moduledoc """
  Represents an image content block within a Claude message.

  Image blocks contain image data either as base64-encoded content or as a URL
  reference. They appear in user messages (vision input) and can also appear in
  tool results.

  ## Source types

    * `"base64"` — inline image with `data` and `media_type`
    * `"url"` — remote image referenced by `url`
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :source]
  defstruct [:type, :source]

  @type source ::
          %{
            type: :base64,
            media_type: String.t(),
            data: String.t()
          }
          | %{
              type: :url,
              url: String.t()
            }

  @type t :: %__MODULE__{
          type: :image,
          source: source()
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "image", "source" => source} = _data) when is_map(source) do
    case parse_source(source) do
      {:ok, parsed} -> {:ok, %__MODULE__{type: :image, source: parsed}}
      error -> error
    end
  end

  def new(%{"type" => "image"}), do: {:error, {:missing_fields, [:source]}}
  def new(_), do: {:error, :invalid_content_type}

  defp parse_source(%{"type" => "base64", "data" => data, "media_type" => media_type}),
    do: {:ok, %{type: :base64, media_type: media_type, data: data}}

  defp parse_source(%{"type" => "base64"} = s), do: {:error, {:missing_fields, missing_keys(s, ["data", "media_type"])}}

  defp parse_source(%{"type" => "url", "url" => url}) when is_binary(url), do: {:ok, %{type: :url, url: url}}

  defp parse_source(%{"type" => "url"}), do: {:error, {:missing_fields, [:url]}}
  defp parse_source(%{"type" => _}), do: {:error, :unknown_source_type}

  defp missing_keys(map, keys), do: for(k <- keys, not Map.has_key?(map, k), do: String.to_atom(k))
end

defimpl String.Chars, for: ClaudeCode.Content.ImageBlock do
  def to_string(%{source: %{type: :base64, media_type: media_type}}), do: "[image: #{media_type}]"

  def to_string(%{source: %{type: :url, url: url}}), do: "[image: #{url}]"
end
