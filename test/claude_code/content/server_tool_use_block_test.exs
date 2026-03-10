defmodule ClaudeCode.Content.ServerToolUseBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ServerToolUseBlock

  describe "new/1" do
    test "creates a server tool use block for web_search" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_123",
        "name" => "web_search",
        "input" => %{"query" => "elixir programming"}
      }

      assert {:ok, block} = ServerToolUseBlock.new(data)
      assert block.type == :server_tool_use
      assert block.id == "srvtoolu_123"
      assert block.name == :web_search
      assert block.input == %{"query" => "elixir programming"}
      assert block.caller == nil
    end

    test "atomizes known server tool names" do
      for name <-
            ~w(web_search web_fetch code_execution bash_code_execution text_editor_code_execution tool_search_tool_regex tool_search_tool_bm25) do
        data = %{
          "type" => "server_tool_use",
          "id" => "srvtoolu_test",
          "name" => name,
          "input" => %{}
        }

        assert {:ok, block} = ServerToolUseBlock.new(data)
        assert block.name == String.to_atom(name)
      end
    end

    test "preserves unknown tool names as strings" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_test",
        "name" => "future_tool",
        "input" => %{}
      }

      assert {:ok, block} = ServerToolUseBlock.new(data)
      assert block.name == "future_tool"
    end

    test "parses caller field when present" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_456",
        "name" => "code_execution",
        "input" => %{"code" => "print('hello')"},
        "caller" => %{"type" => "direct"}
      }

      assert {:ok, block} = ServerToolUseBlock.new(data)
      assert block.caller == %{"type" => "direct"}
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:id, :name, :input]}} =
               ServerToolUseBlock.new(%{"type" => "server_tool_use"})
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_content_type} =
               ServerToolUseBlock.new(%{"type" => "tool_use", "id" => "x", "name" => "y", "input" => %{}})
    end
  end
end
