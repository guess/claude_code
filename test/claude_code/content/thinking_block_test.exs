defmodule ClaudeCode.Content.ThinkingBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ThinkingBlock

  describe "new/1" do
    test "creates a thinking content block from valid data" do
      data = %{
        "type" => "thinking",
        "thinking" => "Let me reason through this problem...",
        "signature" => "sig_abc123"
      }

      assert {:ok, content} = ThinkingBlock.new(data)
      assert content.type == :thinking
      assert content.thinking == "Let me reason through this problem..."
      assert content.signature == "sig_abc123"
    end

    test "handles empty thinking content" do
      data = %{
        "type" => "thinking",
        "thinking" => "",
        "signature" => "sig_empty"
      }

      assert {:ok, content} = ThinkingBlock.new(data)
      assert content.thinking == ""
      assert content.signature == "sig_empty"
    end

    test "handles long thinking content" do
      long_thinking =
        "First, let me understand the problem. Then I'll consider different approaches. " <>
          String.duplicate("This is a detailed analysis. ", 100)

      data = %{
        "type" => "thinking",
        "thinking" => long_thinking,
        "signature" => "sig_long"
      }

      assert {:ok, content} = ThinkingBlock.new(data)
      assert content.thinking == long_thinking
    end

    test "returns error for invalid type" do
      data = %{
        "type" => "text",
        "thinking" => "Let me think...",
        "signature" => "sig_123"
      }

      assert {:error, :invalid_content_type} = ThinkingBlock.new(data)
    end

    test "returns error for missing thinking field" do
      data = %{"type" => "thinking", "signature" => "sig_123"}

      assert {:error, {:missing_fields, [:thinking]}} = ThinkingBlock.new(data)
    end

    test "returns error for missing signature field" do
      data = %{"type" => "thinking", "thinking" => "Let me reason..."}

      assert {:error, {:missing_fields, [:signature]}} = ThinkingBlock.new(data)
    end

    test "returns error for missing both thinking and signature" do
      data = %{"type" => "thinking"}

      assert {:error, {:missing_fields, missing}} = ThinkingBlock.new(data)
      assert :thinking in missing
      assert :signature in missing
    end

    test "requires both fields regardless of order" do
      data = %{
        "signature" => "sig_123",
        "type" => "thinking",
        "thinking" => "reasoning"
      }

      assert {:ok, content} = ThinkingBlock.new(data)
      assert content.thinking == "reasoning"
      assert content.signature == "sig_123"
    end
  end

  describe "type guards" do
    test "thinking_content?/1 returns true for thinking content" do
      {:ok, content} = ThinkingBlock.new(%{
        "type" => "thinking",
        "thinking" => "Let me think...",
        "signature" => "sig_123"
      })

      assert ThinkingBlock.thinking_content?(content)
    end

    test "thinking_content?/1 returns false for non-thinking content" do
      refute ThinkingBlock.thinking_content?(%{type: :text})
      refute ThinkingBlock.thinking_content?(%{type: :tool_use})
      refute ThinkingBlock.thinking_content?(nil)
      refute ThinkingBlock.thinking_content?("not content")
      refute ThinkingBlock.thinking_content?(%{})
    end
  end

  describe "struct properties" do
    test "has required fields" do
      data = %{
        "type" => "thinking",
        "thinking" => "Some reasoning",
        "signature" => "sig_xyz"
      }

      {:ok, content} = ThinkingBlock.new(data)
      
      # Verify all required fields are present
      assert Map.has_key?(content, :type)
      assert Map.has_key?(content, :thinking)
      assert Map.has_key?(content, :signature)
    end
  end

  describe "real world usage" do
    test "parses thinking content with special characters" do
      data = %{
        "type" => "thinking",
        "thinking" => "Let me analyze: 1) First point, 2) Second point\nWith newlines!",
        "signature" => "sig_special"
      }

      assert {:ok, content} = ThinkingBlock.new(data)
      assert content.thinking == "Let me analyze: 1) First point, 2) Second point\nWith newlines!"
    end

    test "handles various signature formats" do
      signatures = [
        "sig_simple",
        "signature-with-dashes",
        "signature_with_underscores",
        "123numeric",
        "mixed_123-abc"
      ]

      Enum.each(signatures, fn sig ->
        data = %{
          "type" => "thinking",
          "thinking" => "reasoning",
          "signature" => sig
        }

        assert {:ok, content} = ThinkingBlock.new(data)
        assert content.signature == sig
      end)
    end
  end
end
