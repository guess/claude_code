defmodule ClaudeCode.MCP.Backend.AnubisTest do
  use ExUnit.Case, async: true

  alias Anubis.MCP.Error
  alias ClaudeCode.MCP.Backend.Anubis, as: Backend
  alias ClaudeCode.MCP.Server

  # Use the tool macro to generate real Anubis Component modules
  defmodule TestServer do
    @moduledoc false
    use Server, name: "anubis-test"

    tool :add do
      description "Add two numbers"

      field(:x, :integer, required: true)
      field(:y, :integer, required: true)

      def execute(%{x: x, y: y}) do
        {:ok, "#{x + y}"}
      end
    end

    tool :return_map do
      description "Return structured data"

      field(:key, :string, required: true)

      def execute(%{key: key}) do
        {:ok, %{key: key, value: "data"}}
      end
    end

    tool :failing_tool do
      description "Always fails"

      def execute(_params) do
        {:error, "Something went wrong"}
      end
    end

    tool :raise_tool do
      description "Raises"

      field(:should_raise, :boolean, required: true)

      def execute(%{should_raise: should_raise}) do
        if should_raise, do: raise("kaboom")

        {:ok, "no raise"}
      end
    end
  end

  describe "list_tools/1" do
    test "returns tool definitions" do
      tools = Backend.list_tools(TestServer)
      assert length(tools) == 4
      add = Enum.find(tools, &(&1["name"] == "add"))
      assert add["description"] == "Add two numbers"
      assert add["inputSchema"]["type"] == "object"
    end
  end

  describe "server_info/1" do
    test "returns server name and version" do
      info = Backend.server_info(TestServer)
      assert info["name"] == "anubis-test"
      assert info["version"] == "1.0.0"
    end
  end

  describe "call_tool/4" do
    test "text result" do
      assert {:ok, result} = Backend.call_tool(TestServer, "add", %{"x" => 5, "y" => 3}, %{})
      assert result["content"] == [%{"type" => "text", "text" => "8"}]
      assert result["isError"] == false
    end

    test "JSON result for maps" do
      assert {:ok, result} =
               Backend.call_tool(TestServer, "return_map", %{"key" => "hello"}, %{})

      [%{"type" => "text", "text" => json}] = result["content"]
      decoded = Jason.decode!(json)
      assert decoded["key"] == "hello"
    end

    test "error result" do
      assert {:ok, result} =
               Backend.call_tool(TestServer, "failing_tool", %{}, %{})

      assert result["isError"] == true
      [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "Something went wrong"
    end

    test "unknown tool returns Error struct" do
      assert {:error, %Error{} = error} = Backend.call_tool(TestServer, "nonexistent", %{}, %{})
      assert error.code == -32_601
    end

    test "exception handling" do
      assert {:ok, result} = Backend.call_tool(TestServer, "raise_tool", %{"should_raise" => true}, %{})
      assert result["isError"] == true
      [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "kaboom"
    end

    test "passes assigns to tool via frame" do
      defmodule AssignsServer do
        @moduledoc false
        use Server, name: "assigns-test"

        tool :whoami do
          description "Returns user"

          def execute(_params, frame) do
            case frame.assigns do
              %{user: user} -> {:ok, "User: #{user}"}
              _ -> {:error, "No user"}
            end
          end
        end
      end

      assert {:ok, result} = Backend.call_tool(AssignsServer, "whoami", %{}, %{user: "alice"})
      assert result["content"] == [%{"type" => "text", "text" => "User: alice"}]
    end

    test "validates params with Peri" do
      assert {:error, %Error{} = error} =
               Backend.call_tool(TestServer, "add", %{"x" => "not_a_number", "y" => 3}, %{})

      assert error.code == -32_602
    end

    test "rejects missing required params" do
      assert {:error, %Error{} = error} =
               Backend.call_tool(TestServer, "add", %{"x" => 5}, %{})

      assert error.code == -32_602
    end
  end

  describe "compatible?/1" do
    test "returns false for regular modules" do
      refute Backend.compatible?(String)
    end
  end
end
