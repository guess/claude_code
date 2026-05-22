defmodule ClaudeCode.Content.SearchResultBlock do
  @moduledoc """
  Represents a search result content block within a Claude message.

  Search result blocks appear in user messages when web search results are
  round-tripped through the CLI. They contain the source URL, title, and
  text content snippets.

  ## Fields

  - `:type` - Always `:search_result`
  - `:source` - URL of the search result
  - `:title` - Title of the search result
  - `:content` - List of text content blocks (stored as raw maps)
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :source, :title, :content]
  defstruct [:type, :source, :title, :content]

  @type t :: %__MODULE__{
          type: :search_result,
          source: String.t(),
          title: String.t(),
          content: [map()]
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "search_result", "source" => source, "title" => title, "content" => content} = _data)
      when is_binary(source) and is_binary(title) and is_list(content) do
    {:ok,
     %__MODULE__{
       type: :search_result,
       source: source,
       title: title,
       content: content
     }}
  end

  def new(%{"type" => "search_result"} = data) do
    missing =
      ["source", "title", "content"]
      |> Enum.filter(&(not Map.has_key?(data, &1)))
      |> Enum.map(&String.to_atom/1)

    {:error, {:missing_fields, missing}}
  end

  def new(_), do: {:error, :invalid_content_type}
end

defimpl String.Chars, for: ClaudeCode.Content.SearchResultBlock do
  def to_string(%{title: title}), do: "[search_result: #{title}]"
end
