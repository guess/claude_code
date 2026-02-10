defmodule ClaudeCode.MCP.RouterTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Router

  describe "handle_request/2 - initialize" do
    test "returns protocol version and server info" do
      message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert response["result"]["capabilities"]["tools"] == %{}
      assert response["result"]["serverInfo"]["name"] == "test-tools"
    end
  end

  describe "handle_request/2 - notifications/initialized" do
    test "returns empty result" do
      message = %{"jsonrpc" => "2.0", "id" => 2, "method" => "notifications/initialized"}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["result"] == %{}
    end
  end

  describe "handle_request/2 - tools/list" do
    test "returns all registered tools with schemas" do
      message = %{"jsonrpc" => "2.0", "id" => 3, "method" => "tools/list"}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      tools = response["result"]["tools"]
      assert length(tools) == 5

      add_tool = Enum.find(tools, &(&1["name"] == "add"))
      assert add_tool["description"] == "Add two numbers"
      assert add_tool["inputSchema"]["type"] == "object"
      assert add_tool["inputSchema"]["properties"]["x"]["type"] == "integer"
    end
  end

  describe "handle_request/2 - tools/call" do
    test "dispatches to the correct tool and returns result" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{"name" => "add", "arguments" => %{"x" => 5, "y" => 3}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["result"]["content"] == [%{"type" => "text", "text" => "8"}]
      assert response["result"]["isError"] == false
    end

    test "returns JSON content for map results" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "return_map", "arguments" => %{"key" => "hello"}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      [%{"type" => "text", "text" => json}] = response["result"]["content"]
      decoded = Jason.decode!(json)
      assert decoded["key"] == "hello"
      assert decoded["value"] == "data"
    end

    test "returns error content for failing tools" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "tools/call",
        "params" => %{"name" => "failing_tool", "arguments" => %{}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["result"]["isError"] == true
      [%{"type" => "text", "text" => error_text}] = response["result"]["content"]
      assert error_text =~ "Something went wrong"
    end

    test "returns error for unknown tool name" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/call",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] =~ "nonexistent"
    end
  end

  describe "handle_request/2 - unknown method" do
    test "returns method not found error" do
      message = %{"jsonrpc" => "2.0", "id" => 8, "method" => "unknown/method"}
      response = Router.handle_request(ClaudeCode.TestTools, message)

      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] =~ "unknown/method"
    end
  end

  describe "handle_request/2 - tool exception handling" do
    test "catches exceptions and returns error content" do
      defmodule RaisingTools do
        @moduledoc false
        use ClaudeCode.MCP.Server, name: "raising"

        tool :boom, "Raises an error" do
          def execute(_params) do
            raise "kaboom"
          end
        end
      end

      message = %{
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "tools/call",
        "params" => %{"name" => "boom", "arguments" => %{}}
      }

      response = Router.handle_request(RaisingTools, message)

      assert response["result"]["isError"] == true
      [%{"type" => "text", "text" => error_text}] = response["result"]["content"]
      assert error_text =~ "kaboom"
    end
  end
end
