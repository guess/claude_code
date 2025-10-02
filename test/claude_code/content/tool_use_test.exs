defmodule ClaudeCode.Content.ToolUseTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ToolUse

  describe "new/1" do
    test "creates a tool use content block from valid data" do
      data = %{
        "type" => "tool_use",
        "id" => "toolu_123",
        "name" => "Read",
        "input" => %{"file_path" => "/test.txt"}
      }

      assert {:ok, content} = ToolUse.new(data)
      assert content.type == :tool_use
      assert content.id == "toolu_123"
      assert content.name == "Read"
      assert content.input == %{"file_path" => "/test.txt"}
    end

    test "handles empty input map" do
      data = %{
        "type" => "tool_use",
        "id" => "toolu_456",
        "name" => "LS",
        "input" => %{}
      }

      assert {:ok, content} = ToolUse.new(data)
      assert content.input == %{}
    end

    test "returns error for invalid type" do
      data = %{
        "type" => "text",
        "id" => "toolu_123",
        "name" => "Read",
        "input" => %{}
      }

      assert {:error, :invalid_content_type} = ToolUse.new(data)
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:id, :name, :input]}} =
               ToolUse.new(%{"type" => "tool_use"})

      assert {:error, {:missing_fields, [:name, :input]}} =
               ToolUse.new(%{"type" => "tool_use", "id" => "123"})

      assert {:error, {:missing_fields, [:input]}} =
               ToolUse.new(%{"type" => "tool_use", "id" => "123", "name" => "Read"})
    end
  end

  describe "type guards" do
    test "tool_use_content?/1 returns true for tool use content" do
      {:ok, content} =
        ToolUse.new(%{
          "type" => "tool_use",
          "id" => "test",
          "name" => "Test",
          "input" => %{}
        })

      assert ToolUse.tool_use_content?(content)
    end

    test "tool_use_content?/1 returns false for non-tool-use content" do
      refute ToolUse.tool_use_content?(%{type: :text})
      refute ToolUse.tool_use_content?(nil)
      refute ToolUse.tool_use_content?("not content")
    end
  end

  describe "from real messages" do
    test "parses tool use from create_file fixture" do
      fixture_path = "test/fixtures/cli_messages/create_file.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find assistant message with tool use
      Enum.each(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
            tool_use = Enum.find(content, &(&1["type"] == "tool_use"))

            if tool_use do
              assert {:ok, parsed} = ToolUse.new(tool_use)
              assert parsed.name == "Write"
              assert parsed.input["file_path"] =~ "test.txt"
              assert parsed.input["content"] == "Hello from Claude"
            end

          _ ->
            :ok
        end
      end)
    end

    test "parses tool use from file_listing fixture" do
      fixture_path = "test/fixtures/cli_messages/file_listing.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find assistant message with LS tool
      Enum.each(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
            tool_use = Enum.find(content, &(&1["type"] == "tool_use"))

            if tool_use do
              assert {:ok, parsed} = ToolUse.new(tool_use)
              assert parsed.name == "LS"
              assert is_binary(parsed.id)
              assert is_map(parsed.input)
            end

          _ ->
            :ok
        end
      end)
    end
  end
end
