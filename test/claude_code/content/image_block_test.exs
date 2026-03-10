defmodule ClaudeCode.Content.ImageBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ImageBlock

  describe "new/1" do
    test "parses base64 image block" do
      data = %{
        "type" => "image",
        "source" => %{
          "type" => "base64",
          "media_type" => "image/png",
          "data" => "iVBORw0KGgo..."
        }
      }

      assert {:ok, block} = ImageBlock.new(data)
      assert block.type == :image
      assert block.source.type == :base64
      assert block.source.media_type == "image/png"
      assert block.source.data == "iVBORw0KGgo..."
    end

    test "parses url image block" do
      data = %{
        "type" => "image",
        "source" => %{
          "type" => "url",
          "url" => "https://example.com/image.png"
        }
      }

      assert {:ok, block} = ImageBlock.new(data)
      assert block.type == :image
      assert block.source.type == :url
      assert block.source.url == "https://example.com/image.png"
    end

    test "returns error when base64 source missing data" do
      data = %{
        "type" => "image",
        "source" => %{"type" => "base64", "media_type" => "image/png"}
      }

      assert {:error, {:missing_fields, [:data]}} = ImageBlock.new(data)
    end

    test "returns error when base64 source missing media_type" do
      data = %{
        "type" => "image",
        "source" => %{"type" => "base64", "data" => "abc"}
      }

      assert {:error, {:missing_fields, [:media_type]}} = ImageBlock.new(data)
    end

    test "returns error when url source missing url" do
      data = %{
        "type" => "image",
        "source" => %{"type" => "url"}
      }

      assert {:error, {:missing_fields, [:url]}} = ImageBlock.new(data)
    end

    test "returns error for unknown source type" do
      data = %{
        "type" => "image",
        "source" => %{"type" => "unknown"}
      }

      assert {:error, :unknown_source_type} = ImageBlock.new(data)
    end

    test "returns error when source is missing" do
      assert {:error, {:missing_fields, [:source]}} = ImageBlock.new(%{"type" => "image"})
    end

    test "returns error for wrong type" do
      assert {:error, :invalid_content_type} =
               ImageBlock.new(%{"type" => "text", "source" => %{}})
    end

    test "returns error for non-map input" do
      assert {:error, :invalid_content_type} = ImageBlock.new("not a map")
    end
  end

  describe "String.Chars" do
    test "formats base64 image" do
      block = %ImageBlock{
        type: :image,
        source: %{type: :base64, media_type: "image/jpeg", data: "abc"}
      }

      assert to_string(block) == "[image: image/jpeg]"
    end

    test "formats url image" do
      block = %ImageBlock{
        type: :image,
        source: %{type: :url, url: "https://example.com/img.png"}
      }

      assert to_string(block) == "[image: https://example.com/img.png]"
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON via Jason" do
      block = %ImageBlock{
        type: :image,
        source: %{type: :base64, media_type: "image/png", data: "abc"}
      }

      assert {:ok, json} = Jason.encode(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "image"
      assert decoded["source"]["type"] == "base64"
    end

    test "encodes to JSON via JSON" do
      block = %ImageBlock{
        type: :image,
        source: %{type: :url, url: "https://example.com/img.png"}
      }

      json = JSON.encode!(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "image"
      assert decoded["source"]["type"] == "url"
    end
  end
end
