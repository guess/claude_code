defmodule ClaudeCode.ContentTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content
  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock

  describe "type detection" do
    test "content?/1 returns true for any content type" do
      {:ok, text} = TextBlock.new(%{"type" => "text", "text" => "Hi"})

      {:ok, thinking} =
        ThinkingBlock.new(%{"type" => "thinking", "thinking" => "reasoning", "signature" => "sig_1"})

      {:ok, tool} = ToolUseBlock.new(%{"type" => "tool_use", "id" => "1", "name" => "X", "input" => %{}})
      {:ok, result} = ToolResultBlock.new(%{"type" => "tool_result", "tool_use_id" => "1", "content" => "OK"})

      assert Content.content?(text)
      assert Content.content?(thinking)
      assert Content.content?(tool)
      assert Content.content?(result)
    end

    test "content?/1 returns false for non-content" do
      refute Content.content?(%{})
      refute Content.content?("string")
      refute Content.content?(nil)
      refute Content.content?([])
    end
  end

  describe "content type helpers" do
    test "content_type/1 returns the type of content" do
      {:ok, text} = TextBlock.new(%{"type" => "text", "text" => "Hi"})

      {:ok, thinking} =
        ThinkingBlock.new(%{"type" => "thinking", "thinking" => "reasoning", "signature" => "sig_1"})

      {:ok, tool} = ToolUseBlock.new(%{"type" => "tool_use", "id" => "1", "name" => "X", "input" => %{}})
      {:ok, result} = ToolResultBlock.new(%{"type" => "tool_result", "tool_use_id" => "1", "content" => "OK"})

      assert Content.content_type(text) == :text
      assert Content.content_type(thinking) == :thinking
      assert Content.content_type(tool) == :tool_use
      assert Content.content_type(result) == :tool_result
    end
  end

  describe "parse_delta/1" do
    test "parses text_delta" do
      assert {:ok, %{type: :text_delta, text: "Hello"}} =
               Content.parse_delta(%{"type" => "text_delta", "text" => "Hello"})
    end

    test "parses input_json_delta" do
      assert {:ok, %{type: :input_json_delta, partial_json: "{\"key\":"}} =
               Content.parse_delta(%{"type" => "input_json_delta", "partial_json" => "{\"key\":"})
    end

    test "parses thinking_delta" do
      assert {:ok, %{type: :thinking_delta, thinking: "Let me think..."}} =
               Content.parse_delta(%{"type" => "thinking_delta", "thinking" => "Let me think..."})
    end

    test "parses signature_delta" do
      assert {:ok, %{type: :signature_delta, signature: "sig_abc"}} =
               Content.parse_delta(%{"type" => "signature_delta", "signature" => "sig_abc"})
    end

    test "parses citations_delta" do
      citation = %{"type" => "char_location", "cited_text" => "text"}

      assert {:ok, %{type: :citations_delta, citation: ^citation}} =
               Content.parse_delta(%{"type" => "citations_delta", "citation" => citation})
    end

    test "parses compaction_delta" do
      assert {:ok, %{type: :compaction_delta, content: "summary"}} =
               Content.parse_delta(%{"type" => "compaction_delta", "content" => "summary"})
    end

    test "parses compaction_delta with nil content" do
      assert {:ok, %{type: :compaction_delta, content: nil}} =
               Content.parse_delta(%{"type" => "compaction_delta", "content" => nil})
    end

    test "returns error for unknown delta type" do
      assert {:error, {:unknown_delta_type, "future_delta"}} =
               Content.parse_delta(%{"type" => "future_delta", "data" => "x"})
    end

    test "returns error for non-map input" do
      assert {:error, :missing_type} = Content.parse_delta("not a map")
    end
  end
end
