defmodule ClaudeCode.Content.TextTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.Text

  describe "new/1" do
    test "creates a text content block from valid data" do
      data = %{"type" => "text", "text" => "Hello, world!"}

      assert {:ok, content} = Text.new(data)
      assert content.type == :text
      assert content.text == "Hello, world!"
    end

    test "handles empty text" do
      data = %{"type" => "text", "text" => ""}

      assert {:ok, content} = Text.new(data)
      assert content.text == ""
    end

    test "returns error for invalid type" do
      data = %{"type" => "tool_use", "text" => "Hello"}

      assert {:error, :invalid_content_type} = Text.new(data)
    end

    test "returns error for missing text field" do
      data = %{"type" => "text"}

      assert {:error, :missing_text} = Text.new(data)
    end

    test "returns error for non-string text" do
      data = %{"type" => "text", "text" => 123}

      assert {:error, :invalid_text} = Text.new(data)
    end
  end

  describe "type guards" do
    test "text_content?/1 returns true for text content" do
      {:ok, content} = Text.new(%{"type" => "text", "text" => "Hi"})
      assert Text.text_content?(content)
    end

    test "text_content?/1 returns false for non-text content" do
      refute Text.text_content?(%{type: :tool_use})
      refute Text.text_content?(nil)
      refute Text.text_content?("not content")
    end
  end

  describe "from real messages" do
    test "parses text content from assistant message fixture" do
      # Load a fixture with text content
      fixture_path = "test/fixtures/cli_messages/simple_hello.json"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find assistant message (should be second line)
      {:ok, json} = Jason.decode(Enum.at(lines, 1))

      assert json["type"] == "assistant"
      content_block = hd(json["message"]["content"])

      assert {:ok, text} = Text.new(content_block)
      assert text.type == :text
      assert text.text =~ "Hello"
    end
  end
end
