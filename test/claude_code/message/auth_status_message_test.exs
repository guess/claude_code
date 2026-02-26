defmodule ClaudeCode.Message.AuthStatusMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.AuthStatusMessage

  describe "new/1" do
    test "parses a valid auth status message with all fields" do
      json = %{
        "type" => "auth_status",
        "isAuthenticating" => true,
        "output" => ["Authenticating...", "Redirecting to browser"],
        "error" => nil,
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = AuthStatusMessage.new(json)
      assert message.type == :auth_status
      assert message.is_authenticating == true
      assert message.output == ["Authenticating...", "Redirecting to browser"]
      assert message.error == nil
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses auth status with error" do
      json = %{
        "type" => "auth_status",
        "isAuthenticating" => false,
        "output" => [],
        "error" => "Authentication failed: invalid token",
        "uuid" => "uuid-456",
        "session_id" => "session-def"
      }

      assert {:ok, message} = AuthStatusMessage.new(json)
      assert message.is_authenticating == false
      assert message.error == "Authentication failed: invalid token"
    end

    test "defaults output to empty list when missing" do
      json = %{
        "type" => "auth_status",
        "isAuthenticating" => true,
        "session_id" => "session-abc"
      }

      assert {:ok, message} = AuthStatusMessage.new(json)
      assert message.output == []
    end

    test "returns error for missing required fields" do
      json = %{"type" => "auth_status"}
      assert {:error, :missing_required_fields} = AuthStatusMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "user"}
      assert {:error, :invalid_message_type} = AuthStatusMessage.new(json)
    end
  end
end
