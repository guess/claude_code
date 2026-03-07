defmodule ClaudeCode.Message.ElicitationCompleteMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.ElicitationCompleteMessage

  describe "new/1" do
    test "parses a valid elicitation_complete message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "mcp_server_name" => "my-server",
        "elicitation_id" => "elicit-abc123",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ElicitationCompleteMessage.new(json)
      assert message.type == :system
      assert message.subtype == :elicitation_complete
      assert message.mcp_server_name == "my-server"
      assert message.elicitation_id == "elicit-abc123"
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses with optional uuid absent" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "mcp_server_name" => "server-name",
        "elicitation_id" => "elicit-1",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ElicitationCompleteMessage.new(json)
      assert message.uuid == nil
    end

    test "returns error for missing mcp_server_name" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "elicitation_id" => "elicit-1",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = ElicitationCompleteMessage.new(json)
    end

    test "returns error for missing elicitation_id" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "mcp_server_name" => "server-name",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = ElicitationCompleteMessage.new(json)
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "mcp_server_name" => "server-name",
        "elicitation_id" => "elicit-1"
      }

      assert {:error, :missing_required_fields} = ElicitationCompleteMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = ElicitationCompleteMessage.new(json)
    end

    test "returns error for wrong subtype" do
      json = %{"type" => "system", "subtype" => "init"}
      assert {:error, :invalid_message_type} = ElicitationCompleteMessage.new(json)
    end
  end

  describe "elicitation_complete_message?/1" do
    test "returns true for an ElicitationCompleteMessage struct" do
      message = %ElicitationCompleteMessage{
        type: :system,
        subtype: :elicitation_complete,
        mcp_server_name: "server",
        elicitation_id: "elicit-1",
        session_id: "session-1"
      }

      assert ElicitationCompleteMessage.elicitation_complete_message?(message) == true
    end

    test "returns false for other values" do
      assert ElicitationCompleteMessage.elicitation_complete_message?(%{}) == false
      assert ElicitationCompleteMessage.elicitation_complete_message?(nil) == false
      assert ElicitationCompleteMessage.elicitation_complete_message?("string") == false
    end
  end
end
