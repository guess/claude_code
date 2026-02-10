defmodule ClaudeCode.Tool.ServerTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.TestTools.Add
  alias ClaudeCode.TestTools.FailingTool
  alias ClaudeCode.TestTools.GetTime
  alias ClaudeCode.TestTools.Greet
  alias ClaudeCode.TestTools.ReturnMap
  alias ClaudeCode.Tool.Server
  alias Hermes.Server.Response

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

  describe "execute/2 wrapping" do
    setup do
      %{frame: %Hermes.Server.Frame{assigns: %{}}}
    end

    test "wraps {:ok, binary} into {:reply, text_response, frame}", %{frame: frame} do
      assert {:reply, response, ^frame} =
               Add.execute(%{x: 3, y: 4}, frame)

      protocol = Response.to_protocol(response)
      assert protocol["content"] == [%{"type" => "text", "text" => "7"}]
      assert protocol["isError"] == false
    end

    test "wraps {:ok, map} into {:reply, json_response, frame}", %{frame: frame} do
      assert {:reply, response, ^frame} =
               ReturnMap.execute(%{key: "test"}, frame)

      protocol = Response.to_protocol(response)
      [%{"type" => "text", "text" => json_text}] = protocol["content"]
      decoded = Jason.decode!(json_text)
      assert decoded["key"] == "test"
      assert decoded["value"] == "data"
    end

    test "wraps {:error, message} into {:error, Error, frame}", %{frame: frame} do
      assert {:error, %Hermes.MCP.Error{message: "Something went wrong"}, ^frame} =
               FailingTool.execute(%{}, frame)
    end

    test "execute/1 tools receive params without frame", %{frame: frame} do
      assert {:reply, response, ^frame} =
               GetTime.execute(%{}, frame)

      protocol = Response.to_protocol(response)
      [%{"type" => "text", "text" => time_str}] = protocol["content"]
      assert {:ok, _, _} = DateTime.from_iso8601(time_str)
    end
  end

  describe "sdk_server?/1" do
    test "returns true for Tool.Server modules" do
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
