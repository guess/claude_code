defmodule ClaudeCode.Message.TaskStartedMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.TaskStartedMessage

  describe "new/1" do
    test "parses a valid task_started message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "task_started",
        "task_id" => "task_abc123",
        "tool_use_id" => "toolu_abc123",
        "description" => "Running background analysis",
        "task_type" => "background",
        "uuid" => "uuid-456",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskStartedMessage.new(json)
      assert message.type == :system
      assert message.subtype == :task_started
      assert message.task_id == "task_abc123"
      assert message.tool_use_id == "toolu_abc123"
      assert message.description == "Running background analysis"
      assert message.task_type == "background"
      assert message.uuid == "uuid-456"
      assert message.session_id == "session-xyz"
    end

    test "handles optional fields when absent" do
      json = %{
        "type" => "system",
        "subtype" => "task_started",
        "task_id" => "task_abc123",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = TaskStartedMessage.new(json)
      assert message.tool_use_id == nil
      assert message.description == nil
      assert message.task_type == nil
      assert message.uuid == nil
    end

    test "returns error for missing task_id" do
      json = %{
        "type" => "system",
        "subtype" => "task_started",
        "session_id" => "session-xyz"
      }

      assert {:error, :missing_required_fields} = TaskStartedMessage.new(json)
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "system",
        "subtype" => "task_started",
        "task_id" => "task_abc123"
      }

      assert {:error, :missing_required_fields} = TaskStartedMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = TaskStartedMessage.new(json)
    end
  end

  describe "task_started_message?/1" do
    test "returns true for a TaskStartedMessage struct" do
      message = %TaskStartedMessage{
        type: :system,
        subtype: :task_started,
        task_id: "task-1",
        session_id: "session-1"
      }

      assert TaskStartedMessage.task_started_message?(message) == true
    end

    test "returns false for other values" do
      assert TaskStartedMessage.task_started_message?(%{}) == false
      assert TaskStartedMessage.task_started_message?(nil) == false
      assert TaskStartedMessage.task_started_message?("string") == false
    end
  end
end
