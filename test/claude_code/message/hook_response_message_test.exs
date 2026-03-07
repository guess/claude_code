defmodule ClaudeCode.Message.HookResponseMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.HookResponseMessage

  describe "new/1" do
    test "parses a valid hook_response message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "hook_response",
        "session_id" => "session-abc",
        "uuid" => "uuid-123",
        "hook_id" => "hook_abc123",
        "hook_name" => "my_hook",
        "hook_event" => "on_tool_start",
        "output" => "done",
        "stdout" => "done",
        "stderr" => nil,
        "exit_code" => 0,
        "outcome" => "success"
      }

      assert {:ok, message} = HookResponseMessage.new(json)
      assert message.type == :system
      assert message.subtype == :hook_response
      assert message.session_id == "session-abc"
      assert message.uuid == "uuid-123"
      assert message.hook_id == "hook_abc123"
      assert message.hook_name == "my_hook"
      assert message.hook_event == "on_tool_start"
      assert message.output == "done"
      assert message.stdout == "done"
      assert message.stderr == nil
      assert message.exit_code == 0
      assert message.outcome == :success
    end

    test "parses outcome string to :success atom" do
      json = base_json("success")
      assert {:ok, message} = HookResponseMessage.new(json)
      assert message.outcome == :success
    end

    test "parses outcome string to :error atom" do
      json = base_json("error")
      assert {:ok, message} = HookResponseMessage.new(json)
      assert message.outcome == :error
    end

    test "parses outcome string to :cancelled atom" do
      json = base_json("cancelled")
      assert {:ok, message} = HookResponseMessage.new(json)
      assert message.outcome == :cancelled
    end

    test "parses unknown outcome to nil" do
      json = base_json("unknown_outcome")
      assert {:ok, message} = HookResponseMessage.new(json)
      assert message.outcome == nil
    end

    test "handles nil exit_code" do
      json = %{
        "type" => "system",
        "subtype" => "hook_response",
        "session_id" => "session-abc",
        "hook_id" => "hook_abc123",
        "hook_name" => "my_hook",
        "hook_event" => "on_tool_start",
        "exit_code" => nil
      }

      assert {:ok, message} = HookResponseMessage.new(json)
      assert message.exit_code == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "hook_response"}
      assert {:error, :missing_required_fields} = HookResponseMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = HookResponseMessage.new(json)
    end
  end

  describe "hook_response_message?/1" do
    test "returns true for a HookResponseMessage struct" do
      message = %HookResponseMessage{
        type: :system,
        subtype: :hook_response,
        session_id: "session-1",
        hook_id: "hook-1",
        hook_name: "test",
        hook_event: "on_tool_start"
      }

      assert HookResponseMessage.hook_response_message?(message) == true
    end

    test "returns false for other values" do
      assert HookResponseMessage.hook_response_message?(%{}) == false
      assert HookResponseMessage.hook_response_message?(nil) == false
      assert HookResponseMessage.hook_response_message?("string") == false
    end
  end

  defp base_json(outcome) do
    %{
      "type" => "system",
      "subtype" => "hook_response",
      "session_id" => "session-abc",
      "hook_id" => "hook_abc123",
      "hook_name" => "my_hook",
      "hook_event" => "on_tool_start",
      "outcome" => outcome
    }
  end
end
