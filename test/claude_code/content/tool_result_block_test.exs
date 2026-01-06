defmodule ClaudeCode.Content.ToolResultBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ToolResultBlock

  describe "new/1" do
    test "creates a successful tool result from valid data" do
      data = %{
        "type" => "tool_result",
        "tool_use_id" => "toolu_123",
        "content" => "File created successfully"
      }

      assert {:ok, result} = ToolResultBlock.new(data)
      assert result.type == :tool_result
      assert result.tool_use_id == "toolu_123"
      assert result.content == "File created successfully"
      assert result.is_error == false
    end

    test "creates an error tool result" do
      data = %{
        "type" => "tool_result",
        "tool_use_id" => "toolu_456",
        "content" => "File does not exist.",
        "is_error" => true
      }

      assert {:ok, result} = ToolResultBlock.new(data)
      assert result.is_error == true
    end

    test "defaults is_error to false when not specified" do
      data = %{
        "type" => "tool_result",
        "tool_use_id" => "toolu_789",
        "content" => "Success"
      }

      assert {:ok, result} = ToolResultBlock.new(data)
      assert result.is_error == false
    end

    test "returns error for invalid type" do
      data = %{
        "type" => "text",
        "tool_use_id" => "123",
        "content" => "Hello"
      }

      assert {:error, :invalid_content_type} = ToolResultBlock.new(data)
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:tool_use_id, :content]}} =
               ToolResultBlock.new(%{"type" => "tool_result"})

      assert {:error, {:missing_fields, [:content]}} =
               ToolResultBlock.new(%{"type" => "tool_result", "tool_use_id" => "123"})
    end
  end

  describe "type guards" do
    test "tool_result_content?/1 returns true for tool result content" do
      {:ok, result} =
        ToolResultBlock.new(%{
          "type" => "tool_result",
          "tool_use_id" => "test",
          "content" => "OK"
        })

      assert ToolResultBlock.tool_result_content?(result)
    end

    test "tool_result_content?/1 returns false for non-tool-result content" do
      refute ToolResultBlock.tool_result_content?(%{type: :text})
      refute ToolResultBlock.tool_result_content?(nil)
      refute ToolResultBlock.tool_result_content?("not content")
    end
  end

  describe "from real messages" do
    test "parses successful tool result from create_file fixture" do
      fixture_path = "test/fixtures/cli_messages/create_file.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find user message with tool result
      Enum.each(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => "user", "message" => %{"content" => content}}} ->
            tool_result = Enum.find(content, &(&1["type"] == "tool_result"))

            if tool_result do
              assert {:ok, parsed} = ToolResultBlock.new(tool_result)
              assert parsed.content =~ "successfully"
              assert parsed.is_error == false
            end

          _ ->
            :ok
        end
      end)
    end

    test "parses error tool result from error_case fixture" do
      fixture_path = "test/fixtures/cli_messages/error_case.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find user message with error tool result
      Enum.each(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => "user", "message" => %{"content" => content}}} ->
            tool_result = Enum.find(content, &(&1["type"] == "tool_result"))

            if tool_result && tool_result["is_error"] do
              assert {:ok, parsed} = ToolResultBlock.new(tool_result)
              assert parsed.content == "File does not exist."
              assert parsed.is_error == true
            end

          _ ->
            :ok
        end
      end)
    end
  end
end
