defmodule ClaudeCode.Message.SystemMessage.LocalCommandOutputTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.LocalCommandOutput

  describe "new/1" do
    test "parses a valid local_command_output message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "content" => "command output here",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = LocalCommandOutput.new(json)
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

      assert {:ok, message} = LocalCommandOutput.new(json)
      assert message.uuid == nil
    end

    test "returns error for missing content" do
      json = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = LocalCommandOutput.new(json)
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "content" => "output text"
      }

      assert {:error, :missing_required_fields} = LocalCommandOutput.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = LocalCommandOutput.new(json)
    end
  end

  describe "local_command_output?/1" do
    test "returns true for a LocalCommandOutput struct" do
      message = %LocalCommandOutput{
        type: :system,
        subtype: :local_command_output,
        content: "output",
        session_id: "session-1"
      }

      assert LocalCommandOutput.local_command_output?(message) == true
    end

    test "returns false for other values" do
      assert LocalCommandOutput.local_command_output?(%{}) == false
      assert LocalCommandOutput.local_command_output?(nil) == false
      assert LocalCommandOutput.local_command_output?("string") == false
    end
  end
end
