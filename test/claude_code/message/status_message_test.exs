defmodule ClaudeCode.Message.StatusMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.StatusMessage

  describe "new/1" do
    test "parses a valid status message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "status",
        "status" => "thinking",
        "permissionMode" => "default",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = StatusMessage.new(json)
      assert message.type == :system
      assert message.subtype == :status
      assert message.status == "thinking"
      assert message.permission_mode == :default
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses permissionMode 'default' to :default" do
      json = base_json("default")
      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == :default
    end

    test "parses permissionMode 'acceptEdits' to :accept_edits" do
      json = base_json("acceptEdits")
      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == :accept_edits
    end

    test "parses permissionMode 'bypassPermissions' to :bypass_permissions" do
      json = base_json("bypassPermissions")
      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == :bypass_permissions
    end

    test "parses permissionMode 'delegate' to :delegate" do
      json = base_json("delegate")
      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == :delegate
    end

    test "parses permissionMode 'dontAsk' to :dont_ask" do
      json = base_json("dontAsk")
      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == :dont_ask
    end

    test "parses permissionMode 'plan' to :plan" do
      json = base_json("plan")
      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == :plan
    end

    test "handles nil permission_mode" do
      json = %{
        "type" => "system",
        "subtype" => "status",
        "status" => "thinking",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == nil
    end

    test "handles unknown permissionMode as nil" do
      json = base_json("unknownMode")
      assert {:ok, message} = StatusMessage.new(json)
      assert message.permission_mode == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "status"}
      assert {:error, :missing_required_fields} = StatusMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = StatusMessage.new(json)
    end
  end

  describe "status_message?/1" do
    test "returns true for a StatusMessage struct" do
      message = %StatusMessage{
        type: :system,
        subtype: :status,
        status: "thinking",
        session_id: "session-1"
      }

      assert StatusMessage.status_message?(message) == true
    end

    test "returns false for other values" do
      assert StatusMessage.status_message?(%{}) == false
      assert StatusMessage.status_message?(nil) == false
      assert StatusMessage.status_message?("string") == false
    end
  end

  defp base_json(permission_mode) do
    %{
      "type" => "system",
      "subtype" => "status",
      "status" => "thinking",
      "permissionMode" => permission_mode,
      "session_id" => "session-abc"
    }
  end
end
