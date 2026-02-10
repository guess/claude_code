defmodule ClaudeCode.Adapter.Local.MCPRoutingTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Local

  describe "extract_sdk_mcp_servers/1" do
    test "extracts MCP.Server modules from mcp_servers option" do
      opts = [
        mcp_servers: %{
          "calc" => ClaudeCode.TestTools,
          "ext" => %{command: "npx", args: ["something"]}
        }
      ]

      result = Local.extract_sdk_mcp_servers(opts)
      assert result == %{"calc" => {ClaudeCode.TestTools, %{}}}
    end

    test "extracts MCP.Server modules with assigns" do
      assigns = %{scope: :admin}

      opts = [
        mcp_servers: %{
          "calc" => %{module: ClaudeCode.TestTools, assigns: assigns}
        }
      ]

      result = Local.extract_sdk_mcp_servers(opts)
      assert result == %{"calc" => {ClaudeCode.TestTools, assigns}}
    end

    test "defaults assigns to empty map for map config without assigns" do
      opts = [
        mcp_servers: %{
          "calc" => %{module: ClaudeCode.TestTools}
        }
      ]

      result = Local.extract_sdk_mcp_servers(opts)
      assert result == %{"calc" => {ClaudeCode.TestTools, %{}}}
    end

    test "returns empty map when no mcp_servers" do
      assert Local.extract_sdk_mcp_servers([]) == %{}
    end

    test "returns empty map when no sdk servers in mcp_servers" do
      opts = [mcp_servers: %{"ext" => %{command: "npx", args: ["something"]}}]
      assert Local.extract_sdk_mcp_servers(opts) == %{}
    end
  end

  describe "handle_mcp_message/3" do
    test "dispatches to MCP.Router for known server" do
      servers = %{"calc" => {ClaudeCode.TestTools, %{}}}

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "add", "arguments" => %{"x" => 2, "y" => 3}}
      }

      response = Local.handle_mcp_message("calc", jsonrpc, servers)
      assert response["result"]["content"] == [%{"type" => "text", "text" => "5"}]
    end

    test "returns error for unknown server name" do
      servers = %{"calc" => {ClaudeCode.TestTools, %{}}}
      jsonrpc = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}

      response = Local.handle_mcp_message("unknown", jsonrpc, servers)
      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] =~ "unknown"
    end
  end
end
