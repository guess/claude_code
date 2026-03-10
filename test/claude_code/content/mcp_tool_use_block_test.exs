defmodule ClaudeCode.Content.MCPToolUseBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.MCPToolUseBlock

  describe "new/1" do
    test "creates an MCP tool use block from valid data" do
      data = %{
        "type" => "mcp_tool_use",
        "id" => "mcptoolu_123",
        "name" => "read_file",
        "server_name" => "filesystem",
        "input" => %{"path" => "/tmp/test.txt"}
      }

      assert {:ok, block} = MCPToolUseBlock.new(data)
      assert block.type == :mcp_tool_use
      assert block.id == "mcptoolu_123"
      assert block.name == "read_file"
      assert block.server_name == "filesystem"
      assert block.input == %{"path" => "/tmp/test.txt"}
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:id, :name, :server_name, :input]}} =
               MCPToolUseBlock.new(%{"type" => "mcp_tool_use"})

      assert {:error, {:missing_fields, [:server_name, :input]}} =
               MCPToolUseBlock.new(%{"type" => "mcp_tool_use", "id" => "x", "name" => "y"})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               MCPToolUseBlock.new(%{
                 "type" => "tool_use",
                 "id" => "x",
                 "name" => "y",
                 "server_name" => "z",
                 "input" => %{}
               })
    end
  end
end
