defmodule ClaudeCode.Content.CompactionBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.CompactionBlock

  describe "new/1" do
    test "creates a compaction block with content" do
      data = %{"type" => "compaction", "content" => "Summary of prior conversation context."}

      assert {:ok, block} = CompactionBlock.new(data)
      assert block.type == :compaction
      assert block.content == "Summary of prior conversation context."
    end

    test "creates a compaction block with nil content (failed compaction)" do
      data = %{"type" => "compaction", "content" => nil}

      assert {:ok, block} = CompactionBlock.new(data)
      assert block.type == :compaction
      assert block.content == nil
    end

    test "creates a compaction block without content key" do
      data = %{"type" => "compaction"}

      assert {:ok, block} = CompactionBlock.new(data)
      assert block.content == nil
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               CompactionBlock.new(%{"type" => "text", "content" => "not compaction"})
    end
  end

  describe "String.Chars" do
    test "renders content when present" do
      {:ok, block} = CompactionBlock.new(%{"type" => "compaction", "content" => "summary text"})
      assert to_string(block) == "summary text"
    end

    test "renders placeholder when content is nil" do
      {:ok, block} = CompactionBlock.new(%{"type" => "compaction", "content" => nil})
      assert to_string(block) == "[compaction failed]"
    end
  end
end
