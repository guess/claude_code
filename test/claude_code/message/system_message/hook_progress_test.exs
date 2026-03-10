defmodule ClaudeCode.Message.SystemMessage.HookProgressTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.HookProgress

  describe "new/1" do
    test "parses a valid hook_progress message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "hook_progress",
        "session_id" => "session-abc",
        "uuid" => "uuid-123",
        "hook_id" => "hook_abc123",
        "hook_name" => "my_hook",
        "hook_event" => "on_tool_start",
        "stdout" => "processing...",
        "stderr" => "warning: something",
        "output" => "processing..."
      }

      assert {:ok, message} = HookProgress.new(json)
      assert message.type == :system
      assert message.subtype == :hook_progress
      assert message.session_id == "session-abc"
      assert message.uuid == "uuid-123"
      assert message.hook_id == "hook_abc123"
      assert message.hook_name == "my_hook"
      assert message.hook_event == "on_tool_start"
      assert message.stdout == "processing..."
      assert message.stderr == "warning: something"
      assert message.output == "processing..."
    end

    test "handles optional fields when nil" do
      json = %{
        "type" => "system",
        "subtype" => "hook_progress",
        "session_id" => "session-abc",
        "hook_id" => "hook_abc123",
        "hook_name" => "my_hook",
        "hook_event" => "on_tool_start",
        "stdout" => nil,
        "stderr" => nil,
        "output" => nil
      }

      assert {:ok, message} = HookProgress.new(json)
      assert message.stdout == nil
      assert message.stderr == nil
      assert message.output == nil
    end

    test "handles optional fields when absent" do
      json = %{
        "type" => "system",
        "subtype" => "hook_progress",
        "session_id" => "session-abc",
        "hook_id" => "hook_abc123",
        "hook_name" => "my_hook",
        "hook_event" => "on_tool_start"
      }

      assert {:ok, message} = HookProgress.new(json)
      assert message.stdout == nil
      assert message.stderr == nil
      assert message.output == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "hook_progress"}
      assert {:error, :missing_required_fields} = HookProgress.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = HookProgress.new(json)
    end
  end

  describe "hook_progress?/1" do
    test "returns true for a HookProgress struct" do
      message = %HookProgress{
        type: :system,
        subtype: :hook_progress,
        session_id: "session-1",
        hook_id: "hook-1",
        hook_name: "test",
        hook_event: "on_tool_start"
      }

      assert HookProgress.hook_progress?(message) == true
    end

    test "returns false for other values" do
      assert HookProgress.hook_progress?(%{}) == false
      assert HookProgress.hook_progress?(nil) == false
      assert HookProgress.hook_progress?("string") == false
    end
  end
end
