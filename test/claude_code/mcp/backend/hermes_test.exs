defmodule ClaudeCode.MCP.Backend.HermesTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.MCP.Backend.Hermes, as: Backend
  alias ClaudeCode.MCP.Server

  describe "list_tools/1" do
    test "returns all 5 tools from TestTools" do
      tools = Backend.list_tools(ClaudeCode.TestTools)
      assert length(tools) == 5
    end

    test "returns correct tool definition for add" do
      tools = Backend.list_tools(ClaudeCode.TestTools)
      add_tool = Enum.find(tools, &(&1["name"] == "add"))

      assert add_tool["name"] == "add"
      assert add_tool["description"] == "Add two numbers"
      assert add_tool["inputSchema"]["type"] == "object"
      assert add_tool["inputSchema"]["properties"]["x"]["type"] == "integer"
      assert add_tool["inputSchema"]["properties"]["y"]["type"] == "integer"
    end
  end

  describe "server_info/1" do
    test "returns name and version" do
      info = Backend.server_info(ClaudeCode.TestTools)

      assert info == %{"name" => "test-tools", "version" => "1.0.0"}
    end
  end

  describe "call_tool/4 - text result" do
    test "returns text content for add tool" do
      {:ok, result} = Backend.call_tool(ClaudeCode.TestTools, "add", %{"x" => 5, "y" => 3}, %{})

      assert result["content"] == [%{"type" => "text", "text" => "8"}]
      assert result["isError"] == false
    end
  end

  describe "call_tool/4 - JSON result" do
    test "returns JSON content for return_map tool" do
      {:ok, result} =
        Backend.call_tool(ClaudeCode.TestTools, "return_map", %{"key" => "hello"}, %{})

      [%{"type" => "text", "text" => json}] = result["content"]
      decoded = Jason.decode!(json)
      assert decoded["key"] == "hello"
      assert decoded["value"] == "data"
    end
  end

  describe "call_tool/4 - error result" do
    test "returns error content for failing tool" do
      {:ok, result} = Backend.call_tool(ClaudeCode.TestTools, "failing_tool", %{}, %{})

      assert result["isError"] == true
      [%{"type" => "text", "text" => error_text}] = result["content"]
      assert error_text =~ "Something went wrong"
    end
  end

  describe "call_tool/4 - unknown tool" do
    test "returns error tuple for unknown tool" do
      result = Backend.call_tool(ClaudeCode.TestTools, "nonexistent", %{}, %{})

      assert {:error, message} = result
      assert message =~ "nonexistent"
    end
  end

  describe "call_tool/4 - validation error" do
    test "returns validation_error for invalid param types" do
      result =
        Backend.call_tool(
          ClaudeCode.TestTools,
          "add",
          %{"x" => "not_a_number", "y" => 3},
          %{}
        )

      assert {:validation_error, message} = result
      assert message =~ "Invalid params"
      assert message =~ "x"
    end
  end

  describe "call_tool/4 - assigns passthrough" do
    defmodule AssignsTools do
      @moduledoc false
      use Server, name: "assigns-test"

      tool :read_assigns, "Reads from frame assigns" do
        def execute(_params, frame) do
          case frame.assigns do
            %{user: user} -> {:ok, "user:#{user}"}
            _ -> {:error, "no user"}
          end
        end
      end
    end

    test "passes assigns through to the frame" do
      {:ok, result} =
        Backend.call_tool(AssignsTools, "read_assigns", %{}, %{user: "alice"})

      assert result["content"] == [%{"type" => "text", "text" => "user:alice"}]
      assert result["isError"] == false
    end
  end

  describe "call_tool/4 - exception handling" do
    defmodule RaisingTools do
      @moduledoc false
      use Server, name: "raising-backend"

      tool :boom, "Raises an error" do
        def execute(_params) do
          raise "kaboom"
        end
      end
    end

    test "catches exceptions and returns error content" do
      {:ok, result} = Backend.call_tool(RaisingTools, "boom", %{}, %{})

      assert result["isError"] == true
      [%{"type" => "text", "text" => error_text}] = result["content"]
      assert error_text =~ "kaboom"
    end
  end

  describe "compatible?/1" do
    test "returns false for SDK server modules" do
      refute Backend.compatible?(ClaudeCode.TestTools)
    end

    test "returns false for regular modules without start_link" do
      refute Backend.compatible?(String)
    end

    test "returns false for non-existent modules" do
      refute Backend.compatible?(This.Module.Does.Not.Exist)
    end
  end
end
