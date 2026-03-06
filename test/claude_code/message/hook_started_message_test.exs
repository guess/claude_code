defmodule ClaudeCode.Message.HookStartedMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.HookStartedMessage

  describe "new/1" do
    test "parses a valid hook_started message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "hook_started",
        "session_id" => "session-abc",
        "uuid" => "uuid-123",
        "hook_id" => "hook_abc123",
        "hook_name" => "my_hook",
        "hook_event" => "on_tool_start"
      }

      assert {:ok, message} = HookStartedMessage.new(json)
      assert message.type == :system
      assert message.subtype == :hook_started
      assert message.session_id == "session-abc"
      assert message.uuid == "uuid-123"
      assert message.hook_id == "hook_abc123"
      assert message.hook_name == "my_hook"
      assert message.hook_event == "on_tool_start"
    end

    test "parses hook_started with optional uuid missing" do
      json = %{
        "type" => "system",
        "subtype" => "hook_started",
        "session_id" => "session-abc",
        "hook_id" => "hook_abc123",
        "hook_name" => "my_hook",
        "hook_event" => "on_tool_start"
      }

      assert {:ok, message} = HookStartedMessage.new(json)
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "hook_started"}
      assert {:error, :missing_required_fields} = HookStartedMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = HookStartedMessage.new(json)
    end

    test "returns error for wrong subtype" do
      json = %{"type" => "system", "subtype" => "init"}
      assert {:error, :invalid_message_type} = HookStartedMessage.new(json)
    end
  end

  describe "hook_started_message?/1" do
    test "returns true for a HookStartedMessage struct" do
      message = %HookStartedMessage{
        type: :system,
        subtype: :hook_started,
        session_id: "session-1",
        hook_id: "hook-1",
        hook_name: "test",
        hook_event: "on_tool_start"
      }

      assert HookStartedMessage.hook_started_message?(message) == true
    end

    test "returns false for other values" do
      assert HookStartedMessage.hook_started_message?(%{}) == false
      assert HookStartedMessage.hook_started_message?(nil) == false
      assert HookStartedMessage.hook_started_message?("string") == false
    end
  end
end
