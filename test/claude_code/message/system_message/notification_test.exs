defmodule ClaudeCode.Message.SystemMessage.NotificationTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.Notification

  describe "new/1" do
    test "parses a valid notification message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "notification",
        "key" => "rate_limit_warning",
        "text" => "Approaching rate limit",
        "priority" => "high",
        "color" => "yellow",
        "timeout_ms" => 5000,
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = Notification.new(json)
      assert message.type == :system
      assert message.subtype == :notification
      assert message.key == "rate_limit_warning"
      assert message.text == "Approaching rate limit"
      assert message.priority == :high
      assert message.color == "yellow"
      assert message.timeout_ms == 5000
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses priority 'low' to :low" do
      assert {:ok, message} = Notification.new(base_json("low"))
      assert message.priority == :low
    end

    test "parses priority 'medium' to :medium" do
      assert {:ok, message} = Notification.new(base_json("medium"))
      assert message.priority == :medium
    end

    test "parses priority 'high' to :high" do
      assert {:ok, message} = Notification.new(base_json("high"))
      assert message.priority == :high
    end

    test "parses priority 'immediate' to :immediate" do
      assert {:ok, message} = Notification.new(base_json("immediate"))
      assert message.priority == :immediate
    end

    test "parses unknown priority to nil" do
      assert {:ok, message} = Notification.new(base_json("critical"))
      assert message.priority == nil
    end

    test "handles optional fields when absent" do
      json = %{
        "type" => "system",
        "subtype" => "notification",
        "key" => "info",
        "text" => "Something happened",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = Notification.new(json)
      assert message.priority == nil
      assert message.color == nil
      assert message.timeout_ms == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "notification"}
      assert {:error, :missing_required_fields} = Notification.new(json)
    end

    test "returns error for missing text" do
      json = %{
        "type" => "system",
        "subtype" => "notification",
        "key" => "some_key",
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = Notification.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = Notification.new(json)
    end
  end

  describe "notification?/1" do
    test "returns true for a Notification struct" do
      message = %Notification{
        type: :system,
        subtype: :notification,
        key: "test_key",
        text: "test text",
        session_id: "session-1"
      }

      assert Notification.notification?(message) == true
    end

    test "returns false for other values" do
      assert Notification.notification?(%{}) == false
      assert Notification.notification?(nil) == false
      assert Notification.notification?("string") == false
    end
  end

  defp base_json(priority) do
    %{
      "type" => "system",
      "subtype" => "notification",
      "key" => "test_notification",
      "text" => "Test message",
      "priority" => priority,
      "session_id" => "session-abc"
    }
  end
end
