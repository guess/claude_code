defmodule ClaudeCode.Message.SystemMessage.ElicitationCompleteTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.ElicitationComplete

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

      assert {:ok, message} = ElicitationComplete.new(json)
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

      assert {:ok, message} = ElicitationComplete.new(json)
      assert message.uuid == nil
    end

    test "returns error for missing mcp_server_name" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "elicitation_id" => "elicit-1",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = ElicitationComplete.new(json)
    end

    test "returns error for missing elicitation_id" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "mcp_server_name" => "server-name",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = ElicitationComplete.new(json)
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "mcp_server_name" => "server-name",
        "elicitation_id" => "elicit-1"
      }

      assert {:error, :missing_required_fields} = ElicitationComplete.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = ElicitationComplete.new(json)
    end

    test "returns error for wrong subtype" do
      json = %{"type" => "system", "subtype" => "init"}
      assert {:error, :invalid_message_type} = ElicitationComplete.new(json)
    end
  end

  describe "elicitation_complete?/1" do
    test "returns true for an ElicitationComplete struct" do
      message = %ElicitationComplete{
        type: :system,
        subtype: :elicitation_complete,
        mcp_server_name: "server",
        elicitation_id: "elicit-1",
        session_id: "session-1"
      }

      assert ElicitationComplete.elicitation_complete?(message) == true
    end

    test "returns false for other values" do
      assert ElicitationComplete.elicitation_complete?(%{}) == false
      assert ElicitationComplete.elicitation_complete?(nil) == false
      assert ElicitationComplete.elicitation_complete?("string") == false
    end
  end
end
