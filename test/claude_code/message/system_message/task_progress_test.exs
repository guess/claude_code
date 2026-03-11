defmodule ClaudeCode.Message.SystemMessage.TaskProgressTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.TaskProgress

  describe "new/1" do
    test "parses a valid task_progress message with all fields including usage" do
      json = %{
        "type" => "system",
        "subtype" => "task_progress",
        "task_id" => "task_abc123",
        "tool_use_id" => "toolu_abc123",
        "description" => "Analyzing files...",
        "usage" => %{
          "total_tokens" => 1500,
          "tool_uses" => 3,
          "duration_ms" => 4200
        },
        "last_tool_name" => "Read",
        "summary" => "Analyzed 5 files so far",
        "uuid" => "uuid-456",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskProgress.new(json)
      assert message.type == :system
      assert message.subtype == :task_progress
      assert message.task_id == "task_abc123"
      assert message.tool_use_id == "toolu_abc123"
      assert message.description == "Analyzing files..."
      assert message.usage == %{"total_tokens" => 1500, "tool_uses" => 3, "duration_ms" => 4200}
      assert message.last_tool_name == "Read"
      assert message.summary == "Analyzed 5 files so far"
      assert message.uuid == "uuid-456"
      assert message.session_id == "session-xyz"
    end

    test "handles optional fields when absent" do
      json = %{
        "type" => "system",
        "subtype" => "task_progress",
        "task_id" => "task_abc123",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskProgress.new(json)
      assert message.tool_use_id == nil
      assert message.description == nil
      assert message.usage == nil
      assert message.last_tool_name == nil
      assert message.summary == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "task_progress"}
      assert {:error, :missing_required_fields} = TaskProgress.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = TaskProgress.new(json)
    end
  end

  describe "task_progress?/1" do
    test "returns true for a TaskProgress struct" do
      message = %TaskProgress{
        type: :system,
        subtype: :task_progress,
        task_id: "task-1",
        session_id: "session-1"
      }

      assert TaskProgress.task_progress?(message) == true
    end

    test "returns false for other values" do
      assert TaskProgress.task_progress?(%{}) == false
      assert TaskProgress.task_progress?(nil) == false
      assert TaskProgress.task_progress?("string") == false
    end
  end
end
