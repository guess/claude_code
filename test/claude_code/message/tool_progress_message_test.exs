defmodule ClaudeCode.Message.ToolProgressMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.ToolProgressMessage

  describe "new/1" do
    test "parses a valid tool progress message with all fields" do
      json = %{
        "type" => "tool_progress",
        "tool_use_id" => "toolu_abc123",
        "tool_name" => "Bash",
        "parent_tool_use_id" => "toolu_parent",
        "elapsed_time_seconds" => 5.2,
        "task_id" => "task-123",
        "uuid" => "uuid-789",
        "session_id" => "session-xyz"
      }

      assert {:ok, message} = ToolProgressMessage.new(json)
      assert message.type == :tool_progress
      assert message.tool_use_id == "toolu_abc123"
      assert message.tool_name == "Bash"
      assert message.parent_tool_use_id == "toolu_parent"
      assert message.elapsed_time_seconds == 5.2
      assert message.task_id == "task-123"
      assert message.uuid == "uuid-789"
      assert message.session_id == "session-xyz"
    end

    test "parses tool progress with minimal fields" do
      json = %{
        "type" => "tool_progress",
        "tool_use_id" => "toolu_abc",
        "tool_name" => "Read",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ToolProgressMessage.new(json)
      assert message.tool_name == "Read"
      assert message.parent_tool_use_id == nil
      assert message.elapsed_time_seconds == nil
      assert message.task_id == nil
      assert message.uuid == nil
    end

    test "parses tool progress with null parent_tool_use_id" do
      json = %{
        "type" => "tool_progress",
        "tool_use_id" => "toolu_abc",
        "tool_name" => "Write",
        "parent_tool_use_id" => nil,
        "elapsed_time_seconds" => 0.5,
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ToolProgressMessage.new(json)
      assert message.parent_tool_use_id == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "tool_progress"}
      assert {:error, :missing_required_fields} = ToolProgressMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "system"}
      assert {:error, :invalid_message_type} = ToolProgressMessage.new(json)
    end
  end
end
