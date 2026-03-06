defmodule ClaudeCode.Message.TaskProgressMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.TaskProgressMessage

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
        "uuid" => "uuid-456",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskProgressMessage.new(json)
      assert message.type == :system
      assert message.subtype == :task_progress
      assert message.task_id == "task_abc123"
      assert message.tool_use_id == "toolu_abc123"
      assert message.description == "Analyzing files..."
      assert message.usage == %{"total_tokens" => 1500, "tool_uses" => 3, "duration_ms" => 4200}
      assert message.last_tool_name == "Read"
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

      assert {:ok, message} = TaskProgressMessage.new(json)
      assert message.tool_use_id == nil
      assert message.description == nil
      assert message.usage == nil
      assert message.last_tool_name == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "task_progress"}
      assert {:error, :missing_required_fields} = TaskProgressMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = TaskProgressMessage.new(json)
    end
  end

  describe "task_progress_message?/1" do
    test "returns true for a TaskProgressMessage struct" do
      message = %TaskProgressMessage{
        type: :system,
        subtype: :task_progress,
        task_id: "task-1",
        session_id: "session-1"
      }

      assert TaskProgressMessage.task_progress_message?(message) == true
    end

    test "returns false for other values" do
      assert TaskProgressMessage.task_progress_message?(%{}) == false
      assert TaskProgressMessage.task_progress_message?(nil) == false
      assert TaskProgressMessage.task_progress_message?("string") == false
    end
  end
end
