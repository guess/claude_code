defmodule ClaudeCode.MCP.Backend.AnubisTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Backend.Anubis, as: Backend

  defmodule AnubisAddTool do
    @moduledoc false
    def __tool_name__, do: "add"
    def __description__, do: "Add two numbers"

    def input_schema,
      do: %{
        "type" => "object",
        "properties" => %{"x" => %{"type" => "integer"}, "y" => %{"type" => "integer"}},
        "required" => ["x", "y"]
      }

    def execute(%{x: x, y: y}, _assigns), do: {:ok, "#{x + y}"}
  end

  defmodule AnubisMapTool do
    @moduledoc false
    def __tool_name__, do: "return_map"
    def __description__, do: "Return structured data"

    def input_schema, do: %{"type" => "object", "properties" => %{"key" => %{"type" => "string"}}, "required" => ["key"]}

    def execute(%{key: key}, _assigns), do: {:ok, %{key: key, value: "data"}}
  end

  defmodule AnubisFailTool do
    @moduledoc false
    def __tool_name__, do: "failing_tool"
    def __description__, do: "Always fails"
    def input_schema, do: %{"type" => "object"}
    def execute(_params, _assigns), do: {:error, "Something went wrong"}
  end

  defmodule AnubisRaiseTool do
    @moduledoc false
    def __tool_name__, do: "raise_tool"
    def __description__, do: "Raises"
    def input_schema, do: %{"type" => "object"}
    def execute(_params, _assigns), do: raise("kaboom")
  end

  defmodule AnubisTestServer do
    @moduledoc false

    def __tool_server__,
      do: %{name: "anubis-test", tools: [AnubisAddTool, AnubisMapTool, AnubisFailTool, AnubisRaiseTool]}
  end

  describe "list_tools/1" do
    test "returns tool definitions" do
      tools = Backend.list_tools(AnubisTestServer)
      assert length(tools) == 4
      add = Enum.find(tools, &(&1["name"] == "add"))
      assert add["description"] == "Add two numbers"
      assert add["inputSchema"]["type"] == "object"
    end
  end

  describe "server_info/1" do
    test "returns server name and version" do
      info = Backend.server_info(AnubisTestServer)
      assert info["name"] == "anubis-test"
      assert info["version"] == "1.0.0"
    end
  end

  describe "call_tool/4" do
    test "text result" do
      assert {:ok, result} = Backend.call_tool(AnubisTestServer, "add", %{"x" => 5, "y" => 3}, %{})
      assert result["content"] == [%{"type" => "text", "text" => "8"}]
      assert result["isError"] == false
    end

    test "JSON result for maps" do
      assert {:ok, result} =
               Backend.call_tool(AnubisTestServer, "return_map", %{"key" => "hello"}, %{})

      [%{"type" => "text", "text" => json}] = result["content"]
      decoded = Jason.decode!(json)
      assert decoded["key"] == "hello"
    end

    test "error result" do
      assert {:ok, result} =
               Backend.call_tool(AnubisTestServer, "failing_tool", %{}, %{})

      assert result["isError"] == true
      [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "Something went wrong"
    end

    test "unknown tool" do
      assert {:error, msg} = Backend.call_tool(AnubisTestServer, "nonexistent", %{}, %{})
      assert msg =~ "nonexistent"
    end

    test "exception handling" do
      assert {:ok, result} = Backend.call_tool(AnubisTestServer, "raise_tool", %{}, %{})
      assert result["isError"] == true
      [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "kaboom"
    end

    test "passes assigns to tool" do
      defmodule AssignsTool do
        @moduledoc false
        def __tool_name__, do: "whoami"
        def __description__, do: "Returns user"
        def input_schema, do: %{"type" => "object"}

        def execute(_params, assigns) do
          case assigns do
            %{user: user} -> {:ok, "User: #{user}"}
            _ -> {:error, "No user"}
          end
        end
      end

      defmodule AssignsServer do
        @moduledoc false
        def __tool_server__, do: %{name: "assigns-test", tools: [AssignsTool]}
      end

      assert {:ok, result} = Backend.call_tool(AssignsServer, "whoami", %{}, %{user: "alice"})
      assert result["content"] == [%{"type" => "text", "text" => "User: alice"}]
    end
  end

  describe "compatible?/1" do
    test "returns false for regular modules" do
      refute Backend.compatible?(String)
    end
  end
end
