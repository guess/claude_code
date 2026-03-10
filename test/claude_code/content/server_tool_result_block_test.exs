defmodule ClaudeCode.Content.ServerToolResultBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ServerToolResultBlock

  @known_types ~w(
    web_search_tool_result
    web_fetch_tool_result
    code_execution_tool_result
    bash_code_execution_tool_result
    text_editor_code_execution_tool_result
    tool_search_tool_result
  )

  describe "new/1" do
    test "parses all known server tool result types" do
      for type <- @known_types do
        data = %{
          "type" => type,
          "tool_use_id" => "toolu_#{type}",
          "content" => [%{"type" => "web_search_result", "url" => "https://example.com"}]
        }

        assert {:ok, %ServerToolResultBlock{} = block} = ServerToolResultBlock.new(data)
        assert block.type == String.to_atom(type)
        assert block.tool_use_id == "toolu_#{type}"
        assert block.content == data["content"]
        assert block.caller == nil
      end
    end

    test "parses web_search_tool_result with search results" do
      data = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "toolu_search",
        "content" => [
          %{"type" => "web_search_result", "title" => "Example", "url" => "https://example.com"}
        ]
      }

      assert {:ok, block} = ServerToolResultBlock.new(data)
      assert block.type == :web_search_tool_result
      assert block.tool_use_id == "toolu_search"
      assert [%{"type" => "web_search_result"} | _] = block.content
    end

    test "parses web_search_tool_result with error content" do
      data = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "toolu_search",
        "content" => %{
          "type" => "web_search_tool_result_error",
          "error_code" => "unavailable"
        }
      }

      assert {:ok, block} = ServerToolResultBlock.new(data)
      assert block.type == :web_search_tool_result
      assert block.content == %{"type" => "web_search_tool_result_error", "error_code" => "unavailable"}
    end

    test "parses web_fetch_tool_result" do
      data = %{
        "type" => "web_fetch_tool_result",
        "tool_use_id" => "toolu_fetch",
        "content" => %{"type" => "web_fetch", "url" => "https://example.com", "content" => "page text"}
      }

      assert {:ok, block} = ServerToolResultBlock.new(data)
      assert block.type == :web_fetch_tool_result
    end

    test "parses code_execution_tool_result" do
      data = %{
        "type" => "code_execution_tool_result",
        "tool_use_id" => "toolu_exec",
        "content" => %{"type" => "code_execution_result", "stdout" => "hello", "return_code" => 0}
      }

      assert {:ok, block} = ServerToolResultBlock.new(data)
      assert block.type == :code_execution_tool_result
    end

    test "includes optional caller field" do
      data = %{
        "type" => "web_search_tool_result",
        "tool_use_id" => "toolu_search",
        "content" => [%{"type" => "web_search_result"}],
        "caller" => %{"type" => "direct_caller", "tool_use_id" => "toolu_parent"}
      }

      assert {:ok, block} = ServerToolResultBlock.new(data)
      assert block.caller == %{"type" => "direct_caller", "tool_use_id" => "toolu_parent"}
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, missing}} =
               ServerToolResultBlock.new(%{"type" => "web_search_tool_result"})

      assert :tool_use_id in missing
      assert :content in missing
    end

    test "returns error for missing tool_use_id" do
      data = %{
        "type" => "web_search_tool_result",
        "content" => []
      }

      assert {:error, {:missing_fields, [:tool_use_id]}} = ServerToolResultBlock.new(data)
    end

    test "returns error for unknown type" do
      assert {:error, :invalid_content_type} =
               ServerToolResultBlock.new(%{"type" => "unknown_tool_result"})
    end

    test "returns error for non-map input" do
      assert {:error, :invalid_content_type} = ServerToolResultBlock.new("not a map")
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON via Jason" do
      block = %ServerToolResultBlock{
        type: :web_search_tool_result,
        tool_use_id: "toolu_123",
        content: [%{"type" => "web_search_result"}]
      }

      assert {:ok, json} = Jason.encode(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "web_search_tool_result"
      assert decoded["tool_use_id"] == "toolu_123"
      assert is_list(decoded["content"])
      refute Map.has_key?(decoded, "caller")
    end

    test "encodes to JSON via JSON" do
      block = %ServerToolResultBlock{
        type: :web_search_tool_result,
        tool_use_id: "toolu_123",
        content: [%{"type" => "web_search_result"}]
      }

      json = JSON.encode!(block)
      decoded = Jason.decode!(json)
      assert decoded["type"] == "web_search_tool_result"
    end
  end
end
