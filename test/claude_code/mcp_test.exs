defmodule ClaudeCode.MCPTest do
  use ExUnit.Case

  alias ClaudeCode.MCP

  describe "available?/0" do
    test "returns true when hermes_mcp is loaded" do
      # Since we have hermes_mcp as a dependency in test, it should be available
      assert MCP.available?()
    end
  end

  describe "require_hermes!/0" do
    test "returns :ok when hermes is available" do
      assert MCP.require_hermes!() == :ok
    end
  end
end
