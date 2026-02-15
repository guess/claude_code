defmodule ClaudeCode.Content.ToolUseBlockTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ToolUseBlock

  describe "new/1" do
    test "creates a tool use content block from valid data" do
      data = %{
        "type" => "tool_use",
        "id" => "toolu_123",
        "name" => "Read",
        "input" => %{"file_path" => "/test.txt"}
      }

      assert {:ok, content} = ToolUseBlock.new(data)
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

      assert {:ok, content} = ToolUseBlock.new(data)
      assert content.input == %{}
    end

    test "parses caller field when present" do
      data = %{
        "type" => "tool_use",
        "id" => "toolu_789",
        "name" => "Bash",
        "input" => %{"command" => "ls"},
        "caller" => %{"type" => "direct"}
      }

      assert {:ok, content} = ToolUseBlock.new(data)
      assert content.caller == %{"type" => "direct"}
    end

    test "caller defaults to nil when not present" do
      data = %{
        "type" => "tool_use",
        "id" => "toolu_abc",
        "name" => "Read",
        "input" => %{"file_path" => "/test.txt"}
      }

      assert {:ok, content} = ToolUseBlock.new(data)
      assert content.caller == nil
    end

    test "returns error for invalid type" do
      data = %{
        "type" => "text",
        "id" => "toolu_123",
        "name" => "Read",
        "input" => %{}
      }

      assert {:error, :invalid_content_type} = ToolUseBlock.new(data)
    end

    test "returns error for missing required fields" do
      assert {:error, {:missing_fields, [:id, :name, :input]}} =
               ToolUseBlock.new(%{"type" => "tool_use"})

      assert {:error, {:missing_fields, [:name, :input]}} =
               ToolUseBlock.new(%{"type" => "tool_use", "id" => "123"})

      assert {:error, {:missing_fields, [:input]}} =
               ToolUseBlock.new(%{"type" => "tool_use", "id" => "123", "name" => "Read"})
    end
  end

  describe "type guards" do
    test "tool_use_content?/1 returns true for tool use content" do
      {:ok, content} =
        ToolUseBlock.new(%{
          "type" => "tool_use",
          "id" => "test",
          "name" => "Test",
          "input" => %{}
        })

      assert ToolUseBlock.tool_use_content?(content)
    end

    test "tool_use_content?/1 returns false for non-tool-use content" do
      refute ToolUseBlock.tool_use_content?(%{type: :text})
      refute ToolUseBlock.tool_use_content?(nil)
      refute ToolUseBlock.tool_use_content?("not content")
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
              assert {:ok, parsed} = ToolUseBlock.new(tool_use)
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
              assert {:ok, parsed} = ToolUseBlock.new(tool_use)
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
