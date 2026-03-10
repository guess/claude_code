defmodule ClaudeCode.Content.MCPToolResultBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.MCPToolResultBlock

  describe "new/1" do
    test "creates an MCP tool result block with string content" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_123",
        "content" => "file contents here",
        "is_error" => false
      }

      assert {:ok, block} = MCPToolResultBlock.new(data)
      assert block.type == :mcp_tool_result
      assert block.tool_use_id == "mcptoolu_123"
      assert block.content == "file contents here"
      assert block.is_error == false
    end

    test "creates an MCP tool result block with text block array content" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_456",
        "content" => [%{"type" => "text", "text" => "result text"}],
        "is_error" => false
      }

      assert {:ok, block} = MCPToolResultBlock.new(data)
      assert [%ClaudeCode.Content.TextBlock{text: "result text"}] = block.content
    end

    test "creates an MCP tool result block with error" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_789",
        "content" => "tool execution failed",
        "is_error" => true
      }

      assert {:ok, block} = MCPToolResultBlock.new(data)
      assert block.is_error == true
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:tool_use_id, :content, :is_error]}} =
               MCPToolResultBlock.new(%{"type" => "mcp_tool_result"})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               MCPToolResultBlock.new(%{
                 "type" => "tool_result",
                 "tool_use_id" => "x",
                 "content" => "y",
                 "is_error" => false
               })
    end
  end
end
