defmodule ClaudeCode.MCP.RouterTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Server
  alias ClaudeCode.Test, as: T

  describe "handle_request/2 - initialize" do
    test "returns protocol version and server info" do
      response =
        T.mcp_request(ClaudeCode.TestTools, %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert response["result"]["capabilities"]["tools"] == %{}
      assert response["result"]["serverInfo"]["name"] == "test-tools"
      assert response["result"]["serverInfo"]["version"] == "1.0.0"
    end
  end

  describe "handle_request/2 - notifications" do
    test "returns empty result for notifications/initialized" do
      response = T.mcp_request(ClaudeCode.TestTools, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

      assert response["result"] == %{}
      refute Map.has_key?(response, "id")
    end

    test "returns empty result for notifications/cancelled" do
      response = T.mcp_request(ClaudeCode.TestTools, %{"jsonrpc" => "2.0", "method" => "notifications/cancelled"})

      assert response["result"] == %{}
      refute Map.has_key?(response, "id")
    end

    test "returns empty result for any notification type" do
      response = T.mcp_request(ClaudeCode.TestTools, %{"jsonrpc" => "2.0", "method" => "notifications/progress"})

      assert response["result"] == %{}
      refute Map.has_key?(response, "id")
    end
  end

  describe "mcp_list_tools/1" do
    test "returns all registered tools with schemas" do
      tools = T.mcp_list_tools(ClaudeCode.TestTools)

      assert length(tools) == 5

      add_tool = Enum.find(tools, &(&1["name"] == "add"))
      assert add_tool["description"] == "Add two numbers"
      assert add_tool["inputSchema"]["type"] == "object"
      assert add_tool["inputSchema"]["properties"]["x"]["type"] == "integer"
    end
  end

  describe "mcp_call_tool/3" do
    test "dispatches to the correct tool and returns result" do
      result = T.mcp_call_tool(ClaudeCode.TestTools, "add", %{"x" => 5, "y" => 3})

      assert result["content"] == [%{"type" => "text", "text" => "8"}]
      assert result["isError"] == false
    end

    test "returns JSON content for map results" do
      result = T.mcp_call_tool(ClaudeCode.TestTools, "return_map", %{"key" => "hello"})

      [%{"type" => "text", "text" => json}] = result["content"]
      decoded = Jason.decode!(json)
      assert decoded["key"] == "hello"
      assert decoded["value"] == "data"
    end

    test "returns error content for failing tools" do
      result = T.mcp_call_tool(ClaudeCode.TestTools, "failing_tool", %{})

      assert result["isError"] == true
      [%{"type" => "text", "text" => error_text}] = result["content"]
      assert error_text =~ "Something went wrong"
    end

    test "returns error for unknown tool name" do
      response =
        T.mcp_request(ClaudeCode.TestTools, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "nonexistent", "arguments" => %{}}
        })

      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] =~ "Method not found"
    end
  end

  describe "mcp_call_tool/3 - parameter validation" do
    test "rejects invalid parameter types with -32602 error" do
      response =
        T.mcp_request(ClaudeCode.TestTools, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "add", "arguments" => %{"x" => "not_a_number", "y" => 3}}
        })

      assert response["error"]["code"] == -32_602
    end

    test "rejects missing required parameters with -32602 error" do
      response =
        T.mcp_request(ClaudeCode.TestTools, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "add", "arguments" => %{"x" => 5}}
        })

      assert response["error"]["code"] == -32_602
    end

    test "allows valid params through to execution" do
      result = T.mcp_call_tool(ClaudeCode.TestTools, "add", %{"x" => 5, "y" => 3})

      assert result["content"] == [%{"type" => "text", "text" => "8"}]
    end

    test "allows tools with no schema (empty params)" do
      result = T.mcp_call_tool(ClaudeCode.TestTools, "get_time", %{})

      assert result["content"]
      refute result["isError"]
    end
  end

  describe "handle_request/2 - unknown method" do
    test "returns method not found error" do
      response = T.mcp_request(ClaudeCode.TestTools, %{"jsonrpc" => "2.0", "id" => 1, "method" => "unknown/method"})

      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] =~ "Method not found"
    end
  end

  describe "handle_request/2 - tool exception handling" do
    test "catches exceptions and returns error content" do
      defmodule RaisingTools do
        @moduledoc false
        use Server, name: "raising"

        tool :boom do
          description "Raises an error"

          def execute(_params) do
            raise "kaboom"
          end
        end
      end

      result = T.mcp_call_tool(RaisingTools, "boom", %{})

      assert result["isError"] == true
      [%{"type" => "text", "text" => error_text}] = result["content"]
      assert error_text =~ "kaboom"
    end
  end

  describe "mcp_call_tool/4 - assigns" do
    defmodule ScopedTools do
      @moduledoc false
      use Server, name: "scoped"

      tool :whoami do
        description "Returns the current user from assigns"

        def execute(_params, frame) do
          case frame.assigns do
            %{scope: %{user: user}} -> {:ok, "Current user: #{user}"}
            _ -> {:error, "No scope"}
          end
        end
      end
    end

    test "passes assigns through to the frame" do
      result = T.mcp_call_tool(ScopedTools, "whoami", %{}, assigns: %{scope: %{user: "alice"}})

      assert result["isError"] == false
      assert result["content"] == [%{"type" => "text", "text" => "Current user: alice"}]
    end

    test "defaults to empty assigns when not provided" do
      result = T.mcp_call_tool(ScopedTools, "whoami", %{})

      assert result["isError"] == true
      [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "No scope"
    end
  end
end
