defmodule ClaudeCode.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Server
  alias ClaudeCode.TestTools.Add
  alias ClaudeCode.TestTools.FailingTool
  alias ClaudeCode.TestTools.GetTime
  alias ClaudeCode.TestTools.Greet
  alias ClaudeCode.TestTools.ReturnMap

  describe "__tool_server__/0" do
    test "returns server metadata with name and tool modules" do
      info = ClaudeCode.TestTools.__tool_server__()

      assert info.name == "test-tools"
      assert is_list(info.tools)
      assert length(info.tools) == 5
    end

    test "tool modules are correctly named" do
      %{tools: tools} = ClaudeCode.TestTools.__tool_server__()
      module_names = tools |> Enum.map(& &1) |> Enum.sort()

      assert Add in module_names
      assert Greet in module_names
      assert GetTime in module_names
      assert ReturnMap in module_names
      assert FailingTool in module_names
    end
  end

  describe "generated tool modules" do
    test "have __tool_name__/0 returning the string name" do
      assert Add.__tool_name__() == "add"
      assert Greet.__tool_name__() == "greet"
      assert GetTime.__tool_name__() == "get_time"
    end

    test "have input_schema/0 returning JSON Schema" do
      schema = Add.input_schema()

      assert schema["type"] == "object"
      assert schema["properties"]["x"]["type"] == "integer"
      assert schema["properties"]["y"]["type"] == "integer"
      assert "x" in schema["required"]
      assert "y" in schema["required"]
    end

    test "tool with no fields has empty object schema" do
      schema = GetTime.input_schema()
      assert schema["type"] == "object"
    end

    test "have __description__/0 matching the tool description" do
      assert Add.__description__() == "Add two numbers"
      assert Greet.__description__() == "Greet a user"
    end
  end

  describe "execute/2" do
    test "returns {:ok, value} for text results" do
      assert {:ok, "7"} = Add.execute(%{x: 3, y: 4}, %{})
    end

    test "returns {:ok, map} for map results" do
      assert {:ok, %{key: "test", value: "data"}} = ReturnMap.execute(%{key: "test"}, %{})
    end

    test "returns {:error, message} for failing tools" do
      assert {:error, "Something went wrong"} = FailingTool.execute(%{}, %{})
    end

    test "execute/1 tools ignore assigns" do
      assert {:ok, time_str} = GetTime.execute(%{}, %{})
      assert {:ok, _, _} = DateTime.from_iso8601(time_str)
    end
  end

  describe "execute/2 with assigns" do
    defmodule AssignsTools do
      @moduledoc false
      use Server, name: "assigns-test"

      tool :whoami, "Returns user from assigns" do
        def execute(_params, assigns) do
          case assigns do
            %{user: user} -> {:ok, "User: #{user}"}
            _ -> {:error, "No user"}
          end
        end
      end
    end

    test "passes assigns to arity-2 execute" do
      assert {:ok, "User: alice"} = AssignsTools.Whoami.execute(%{}, %{user: "alice"})
    end

    test "empty assigns when not provided" do
      assert {:error, "No user"} = AssignsTools.Whoami.execute(%{}, %{})
    end
  end

  describe "sdk_server?/1" do
    test "returns true for MCP.Server modules" do
      assert Server.sdk_server?(ClaudeCode.TestTools)
    end

    test "returns false for regular modules" do
      refute Server.sdk_server?(String)
    end

    test "returns false for non-existent modules" do
      refute Server.sdk_server?(DoesNotExist)
    end
  end
end
