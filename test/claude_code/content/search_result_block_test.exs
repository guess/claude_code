defmodule ClaudeCode.Content.SearchResultBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.SearchResultBlock

  describe "new/1" do
    test "parses a valid search_result block" do
      json = %{
        "type" => "search_result",
        "source" => "https://example.com/article",
        "title" => "Example Article",
        "content" => [%{"type" => "text", "text" => "Article snippet..."}]
      }

      assert {:ok, block} = SearchResultBlock.new(json)
      assert block.type == :search_result
      assert block.source == "https://example.com/article"
      assert block.title == "Example Article"
      assert block.content == [%{"type" => "text", "text" => "Article snippet..."}]
    end

    test "parses with multiple content blocks" do
      json = %{
        "type" => "search_result",
        "source" => "https://example.com",
        "title" => "Test",
        "content" => [
          %{"type" => "text", "text" => "First paragraph"},
          %{"type" => "text", "text" => "Second paragraph"}
        ]
      }

      assert {:ok, block} = SearchResultBlock.new(json)
      assert length(block.content) == 2
    end

    test "returns error for missing required fields" do
      json = %{"type" => "search_result", "source" => "https://example.com"}
      assert {:error, {:missing_fields, missing}} = SearchResultBlock.new(json)
      assert :title in missing
      assert :content in missing
    end

    test "returns error for invalid content type" do
      json = %{"type" => "text", "text" => "hello"}
      assert {:error, :invalid_content_type} = SearchResultBlock.new(json)
    end
  end

  describe "String.Chars" do
    test "renders with title" do
      block = %SearchResultBlock{
        type: :search_result,
        source: "https://example.com",
        title: "Example",
        content: []
      }

      assert to_string(block) == "[search_result: Example]"
    end
  end
end
