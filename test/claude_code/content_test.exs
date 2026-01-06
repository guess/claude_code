defmodule ClaudeCode.ContentTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content
  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock

  describe "parse/1" do
    test "parses text content blocks" do
      data = %{"type" => "text", "text" => "Hello!"}

      assert {:ok, %TextBlock{text: "Hello!"}} = Content.parse(data)
    end

    test "parses thinking content blocks" do
      data = %{
        "type" => "thinking",
        "thinking" => "Let me reason through this...",
        "signature" => "sig_abc123"
      }

      assert {:ok, %ThinkingBlock{thinking: "Let me reason through this...", signature: "sig_abc123"}} =
               Content.parse(data)
    end

    test "returns error for thinking block missing signature" do
      data = %{"type" => "thinking", "thinking" => "Some reasoning"}

      assert {:error, {:missing_fields, [:signature]}} = Content.parse(data)
    end

    test "returns error for thinking block missing thinking field" do
      data = %{"type" => "thinking", "signature" => "sig_123"}

      assert {:error, {:missing_fields, [:thinking]}} = Content.parse(data)
    end

    test "parses tool use content blocks" do
      data = %{
        "type" => "tool_use",
        "id" => "toolu_123",
        "name" => "Read",
        "input" => %{"file" => "test.txt"}
      }

      assert {:ok, %ToolUseBlock{id: "toolu_123", name: "Read"}} = Content.parse(data)
    end

    test "parses tool result content blocks" do
      data = %{
        "type" => "tool_result",
        "tool_use_id" => "toolu_123",
        "content" => "Success"
      }

      assert {:ok, %ToolResultBlock{tool_use_id: "toolu_123"}} = Content.parse(data)
    end

    test "returns error for unknown content type" do
      data = %{"type" => "unknown", "data" => "something"}

      assert {:error, {:unknown_content_type, "unknown"}} = Content.parse(data)
    end

    test "returns error for missing type field" do
      data = %{"text" => "Hello"}

      assert {:error, :missing_type} = Content.parse(data)
    end
  end

  describe "parse_all/1" do
    test "parses a list of content blocks" do
      data = [
        %{"type" => "text", "text" => "I'll help you."},
        %{"type" => "tool_use", "id" => "123", "name" => "Read", "input" => %{}},
        %{"type" => "text", "text" => "Done!"}
      ]

      assert {:ok, [text1, tool_use, text2]} = Content.parse_all(data)
      assert %TextBlock{text: "I'll help you."} = text1
      assert %ToolUseBlock{name: "Read"} = tool_use
      assert %TextBlock{text: "Done!"} = text2
    end

    test "returns error if any block fails to parse" do
      data = [
        %{"type" => "text", "text" => "OK"},
        %{"type" => "invalid"},
        %{"type" => "text", "text" => "More"}
      ]

      assert {:error, {:parse_error, 1, _}} = Content.parse_all(data)
    end

    test "handles empty list" do
      assert {:ok, []} = Content.parse_all([])
    end
  end

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
end
