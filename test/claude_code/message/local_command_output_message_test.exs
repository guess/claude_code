defmodule ClaudeCode.Message.LocalCommandOutputMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.LocalCommandOutputMessage

  describe "new/1" do
    test "parses a valid local_command_output message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "content" => "command output here",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = LocalCommandOutputMessage.new(json)
      assert message.type == :system
      assert message.subtype == :local_command_output
      assert message.content == "command output here"
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses with optional uuid absent" do
      json = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "content" => "output text",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = LocalCommandOutputMessage.new(json)
      assert message.uuid == nil
    end

    test "returns error for missing content" do
      json = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = LocalCommandOutputMessage.new(json)
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "content" => "output text"
      }

      assert {:error, :missing_required_fields} = LocalCommandOutputMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = LocalCommandOutputMessage.new(json)
    end
  end

  describe "local_command_output_message?/1" do
    test "returns true for a LocalCommandOutputMessage struct" do
      message = %LocalCommandOutputMessage{
        type: :system,
        subtype: :local_command_output,
        content: "output",
        session_id: "session-1"
      }

      assert LocalCommandOutputMessage.local_command_output_message?(message) == true
    end

    test "returns false for other values" do
      assert LocalCommandOutputMessage.local_command_output_message?(%{}) == false
      assert LocalCommandOutputMessage.local_command_output_message?(nil) == false
      assert LocalCommandOutputMessage.local_command_output_message?("string") == false
    end
  end
end
