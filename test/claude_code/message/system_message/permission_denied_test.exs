defmodule ClaudeCode.Message.SystemMessage.PermissionDeniedTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.PermissionDenied

  describe "new/1" do
    test "parses a valid permission_denied message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "permission_denied",
        "tool_name" => "Bash",
        "tool_use_id" => "toolu_abc123",
        "agent_id" => "agent-1",
        "decision_reason_type" => "user_denied",
        "reason" => "User rejected this action",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = PermissionDenied.new(json)
      assert message.type == :system
      assert message.subtype == :permission_denied
      assert message.tool_name == "Bash"
      assert message.tool_use_id == "toolu_abc123"
      assert message.agent_id == "agent-1"
      assert message.decision_reason_type == "user_denied"
      assert message.reason == "User rejected this action"
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "handles optional fields when absent" do
      json = %{
        "type" => "system",
        "subtype" => "permission_denied",
        "tool_name" => "Write",
        "tool_use_id" => "toolu_xyz",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = PermissionDenied.new(json)
      assert message.agent_id == nil
      assert message.decision_reason_type == nil
      assert message.reason == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "permission_denied"}
      assert {:error, :missing_required_fields} = PermissionDenied.new(json)
    end

    test "returns error for missing tool_use_id" do
      json = %{
        "type" => "system",
        "subtype" => "permission_denied",
        "tool_name" => "Bash",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = PermissionDenied.new(json)
    end

    test "returns error for missing tool_name" do
      json = %{
        "type" => "system",
        "subtype" => "permission_denied",
        "tool_use_id" => "toolu_abc",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = PermissionDenied.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = PermissionDenied.new(json)
    end
  end

  describe "permission_denied?/1" do
    test "returns true for a PermissionDenied struct" do
      message = %PermissionDenied{
        type: :system,
        subtype: :permission_denied,
        tool_name: "Bash",
        tool_use_id: "toolu_1",
        session_id: "session-1"
      }

      assert PermissionDenied.permission_denied?(message) == true
    end

    test "returns false for other values" do
      assert PermissionDenied.permission_denied?(%{}) == false
      assert PermissionDenied.permission_denied?(nil) == false
      assert PermissionDenied.permission_denied?("string") == false
    end
  end
end
