defmodule ClaudeCode.Content.DocumentBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.DocumentBlock

  describe "new/1" do
    test "parses base64 document block" do
      data = %{
        "type" => "document",
        "source" => %{
          "type" => "base64",
          "media_type" => "application/pdf",
          "data" => "JVBERi0xLjQ..."
        }
      }

      assert {:ok, block} = DocumentBlock.new(data)
      assert block.type == :document
      assert block.source.type == :base64
      assert block.source.media_type == "application/pdf"
      assert block.source.data == "JVBERi0xLjQ..."
    end

    test "parses text document block" do
      data = %{
        "type" => "document",
        "source" => %{
          "type" => "text",
          "media_type" => "text/plain",
          "data" => "Hello, world!"
        }
      }

      assert {:ok, block} = DocumentBlock.new(data)
      assert block.source.type == :text
      assert block.source.media_type == "text/plain"
      assert block.source.data == "Hello, world!"
    end

    test "parses url document block" do
      data = %{
        "type" => "document",
        "source" => %{
          "type" => "url",
          "url" => "https://example.com/doc.pdf"
        }
      }

      assert {:ok, block} = DocumentBlock.new(data)
      assert block.source.type == :url
      assert block.source.url == "https://example.com/doc.pdf"
    end

    test "parses content document block" do
      data = %{
        "type" => "document",
        "source" => %{
          "type" => "content",
          "content" => [%{"type" => "text", "text" => "extracted content"}]
        }
      }

      assert {:ok, block} = DocumentBlock.new(data)
      assert block.source.type == :content
      assert block.source.content == [%{"type" => "text", "text" => "extracted content"}]
    end

    test "parses optional title and context" do
      data = %{
        "type" => "document",
        "source" => %{
          "type" => "base64",
          "media_type" => "application/pdf",
          "data" => "abc"
        },
        "title" => "My Document",
        "context" => "Important context"
      }

      assert {:ok, block} = DocumentBlock.new(data)
      assert block.title == "My Document"
      assert block.context == "Important context"
    end

    test "title and context default to nil" do
      data = %{
        "type" => "document",
        "source" => %{
          "type" => "base64",
          "media_type" => "application/pdf",
          "data" => "abc"
        }
      }

      assert {:ok, block} = DocumentBlock.new(data)
      assert block.title == nil
      assert block.context == nil
    end

    test "returns error when base64 source missing data" do
      data = %{
        "type" => "document",
        "source" => %{"type" => "base64", "media_type" => "application/pdf"}
      }

      assert {:error, {:missing_fields, [:data]}} = DocumentBlock.new(data)
    end

    test "returns error when url source missing url" do
      data = %{
        "type" => "document",
        "source" => %{"type" => "url"}
      }

      assert {:error, {:missing_fields, [:url]}} = DocumentBlock.new(data)
    end

    test "returns error when content source missing content" do
      data = %{
        "type" => "document",
        "source" => %{"type" => "content"}
      }

      assert {:error, {:missing_fields, [:content]}} = DocumentBlock.new(data)
    end

    test "returns error for unknown source type" do
      data = %{
        "type" => "document",
        "source" => %{"type" => "unknown"}
      }

      assert {:error, :unknown_source_type} = DocumentBlock.new(data)
    end

    test "returns error when source is missing" do
      assert {:error, {:missing_fields, [:source]}} =
               DocumentBlock.new(%{"type" => "document"})
    end

    test "returns error for wrong type" do
      assert {:error, :invalid_content_type} =
               DocumentBlock.new(%{"type" => "text", "source" => %{}})
    end

    test "returns error for non-map input" do
      assert {:error, :invalid_content_type} = DocumentBlock.new("not a map")
    end
  end

  describe "String.Chars" do
    test "formats document with title" do
      block = %DocumentBlock{
        type: :document,
        source: %{type: :base64, media_type: "application/pdf", data: "abc"},
        title: "My Doc"
      }

      assert to_string(block) == "[document: My Doc]"
    end

    test "formats document without title using source type" do
      block = %DocumentBlock{
        type: :document,
        source: %{type: :base64, media_type: "application/pdf", data: "abc"}
      }

      assert to_string(block) == "[document: base64]"
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON via Jason" do
      block = %DocumentBlock{
        type: :document,
        source: %{type: :base64, media_type: "application/pdf", data: "abc"},
        title: "My Doc"
      }

      assert {:ok, json} = Jason.encode(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "document"
      assert decoded["source"]["type"] == "base64"
      assert decoded["title"] == "My Doc"
    end

    test "encodes to JSON via JSON and omits nils" do
      block = %DocumentBlock{
        type: :document,
        source: %{type: :url, url: "https://example.com/doc.pdf"}
      }

      json = JSON.encode!(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "document"
      refute Map.has_key?(decoded, "title")
      refute Map.has_key?(decoded, "context")
    end
  end
end
