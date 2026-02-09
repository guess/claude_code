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
end
