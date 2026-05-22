defmodule ClaudeCode.Message.SystemMessage.TaskUpdatedTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.TaskUpdated

  describe "new/1" do
    test "parses a valid task_updated message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "task_updated",
        "task_id" => "task_abc123",
        "patch" => %{
          "status" => "running",
          "description" => "Processing files",
          "is_backgrounded" => true
        },
        "uuid" => "uuid-456",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskUpdated.new(json)
      assert message.type == :system
      assert message.subtype == :task_updated
      assert message.task_id == "task_abc123"
      assert message.patch == %{"status" => "running", "description" => "Processing files", "is_backgrounded" => true}
      assert message.uuid == "uuid-456"
      assert message.session_id == "session-xyz"
    end

    test "handles absent optional patch field" do
      json = %{
        "type" => "system",
        "subtype" => "task_updated",
        "task_id" => "task_abc123",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskUpdated.new(json)
      assert message.patch == nil
      assert message.uuid == nil
    end

    test "stores patch as raw map" do
      json = %{
        "type" => "system",
        "subtype" => "task_updated",
        "task_id" => "task_abc123",
        "patch" => %{"end_time" => "2024-01-01T00:00:00Z", "total_paused_ms" => 5000, "error" => "timeout"},
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskUpdated.new(json)
      assert message.patch["end_time"] == "2024-01-01T00:00:00Z"
      assert message.patch["total_paused_ms"] == 5000
      assert message.patch["error"] == "timeout"
    end

    test "returns error for missing required fields (task_id)" do
      json = %{"type" => "system", "subtype" => "task_updated"}
      assert {:error, :missing_required_fields} = TaskUpdated.new(json)
    end

    test "returns error for missing session_id" do
      json = %{"type" => "system", "subtype" => "task_updated", "task_id" => "task_abc"}
      assert {:error, :missing_required_fields} = TaskUpdated.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = TaskUpdated.new(json)
    end
  end

  describe "task_updated?/1" do
    test "returns true for a TaskUpdated struct" do
      message = %TaskUpdated{
        type: :system,
        subtype: :task_updated,
        task_id: "task-1",
        session_id: "session-1"
      }

      assert TaskUpdated.task_updated?(message) == true
    end

    test "returns false for other values" do
      assert TaskUpdated.task_updated?(%{}) == false
      assert TaskUpdated.task_updated?(nil) == false
      assert TaskUpdated.task_updated?("string") == false
    end
  end
end
