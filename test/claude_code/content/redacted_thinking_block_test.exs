defmodule ClaudeCode.Content.RedactedThinkingBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.RedactedThinkingBlock

  describe "new/1" do
    test "creates a redacted thinking block from valid data" do
      data = %{"type" => "redacted_thinking", "data" => "encrypted_abc123"}

      assert {:ok, block} = RedactedThinkingBlock.new(data)
      assert block.type == :redacted_thinking
      assert block.data == "encrypted_abc123"
    end

    test "returns error for missing data field" do
      assert {:error, {:missing_fields, [:data]}} =
               RedactedThinkingBlock.new(%{"type" => "redacted_thinking"})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               RedactedThinkingBlock.new(%{"type" => "thinking", "data" => "abc"})
    end
  end

  describe "String.Chars" do
    test "renders as placeholder text" do
      {:ok, block} = RedactedThinkingBlock.new(%{"type" => "redacted_thinking", "data" => "abc"})
      assert to_string(block) == "[redacted thinking]"
    end
  end
end
