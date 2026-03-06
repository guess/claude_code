defmodule ClaudeCode.Message.TaskNotificationMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.TaskNotificationMessage

  describe "new/1" do
    test "parses a valid task_notification message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "task_notification",
        "task_id" => "task_abc123",
        "tool_use_id" => "toolu_abc123",
        "status" => "completed",
        "output_file" => "/tmp/task_abc123_output.json",
        "summary" => "Analysis complete: found 3 issues",
        "usage" => %{
          "total_tokens" => 5000,
          "tool_uses" => 12,
          "duration_ms" => 15_000
        },
        "uuid" => "uuid-456",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskNotificationMessage.new(json)
      assert message.type == :system
      assert message.subtype == :task_notification
      assert message.task_id == "task_abc123"
      assert message.tool_use_id == "toolu_abc123"
      assert message.status == :completed
      assert message.output_file == "/tmp/task_abc123_output.json"
      assert message.summary == "Analysis complete: found 3 issues"
      assert message.usage == %{"total_tokens" => 5000, "tool_uses" => 12, "duration_ms" => 15_000}
      assert message.uuid == "uuid-456"
      assert message.session_id == "session-xyz"
    end

    test "parses status to :completed atom" do
      json = base_json("completed")
      assert {:ok, message} = TaskNotificationMessage.new(json)
      assert message.status == :completed
    end

    test "parses status to :failed atom" do
      json = base_json("failed")
      assert {:ok, message} = TaskNotificationMessage.new(json)
      assert message.status == :failed
    end

    test "parses status to :stopped atom" do
      json = base_json("stopped")
      assert {:ok, message} = TaskNotificationMessage.new(json)
      assert message.status == :stopped
    end

    test "parses unknown status to nil" do
      json = base_json("unknown_status")
      assert {:ok, message} = TaskNotificationMessage.new(json)
      assert message.status == nil
    end

    test "handles optional usage when absent" do
      json = %{
        "type" => "system",
        "subtype" => "task_notification",
        "task_id" => "task_abc123",
        "status" => "completed",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskNotificationMessage.new(json)
      assert message.usage == nil
      assert message.tool_use_id == nil
      assert message.output_file == nil
      assert message.summary == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "task_notification"}
      assert {:error, :missing_required_fields} = TaskNotificationMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = TaskNotificationMessage.new(json)
    end
  end

  describe "task_notification_message?/1" do
    test "returns true for a TaskNotificationMessage struct" do
      message = %TaskNotificationMessage{
        type: :system,
        subtype: :task_notification,
        task_id: "task-1",
        session_id: "session-1"
      }

      assert TaskNotificationMessage.task_notification_message?(message) == true
    end

    test "returns false for other values" do
      assert TaskNotificationMessage.task_notification_message?(%{}) == false
      assert TaskNotificationMessage.task_notification_message?(nil) == false
      assert TaskNotificationMessage.task_notification_message?("string") == false
    end
  end

  defp base_json(status) do
    %{
      "type" => "system",
      "subtype" => "task_notification",
      "task_id" => "task_abc123",
      "status" => status,
      "session_id" => "session-xyz"
    }
  end
end
