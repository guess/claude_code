defmodule ClaudeCode.Message.SystemMessage.SessionStateChangedTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.SessionStateChanged

  describe "new/1" do
    test "parses idle state" do
      json = %{
        "type" => "system",
        "subtype" => "session_state_changed",
        "state" => "idle",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = SessionStateChanged.new(json)
      assert message.type == :system
      assert message.subtype == :session_state_changed
      assert message.state == :idle
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses running state" do
      json = %{
        "type" => "system",
        "subtype" => "session_state_changed",
        "state" => "running",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = SessionStateChanged.new(json)
      assert message.state == :running
    end

    test "parses requires_action state" do
      json = %{
        "type" => "system",
        "subtype" => "session_state_changed",
        "state" => "requires_action",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = SessionStateChanged.new(json)
      assert message.state == :requires_action
    end

    test "handles missing uuid" do
      json = %{
        "type" => "system",
        "subtype" => "session_state_changed",
        "state" => "idle",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = SessionStateChanged.new(json)
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "session_state_changed"}
      assert {:error, :missing_required_fields} = SessionStateChanged.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = SessionStateChanged.new(json)
    end
  end

  describe "session_state_changed?/1" do
    test "returns true for a SessionStateChanged struct" do
      message = %SessionStateChanged{
        type: :system,
        subtype: :session_state_changed,
        state: :idle,
        session_id: "session-1"
      }

      assert SessionStateChanged.session_state_changed?(message) == true
    end

    test "returns false for other values" do
      assert SessionStateChanged.session_state_changed?(%{}) == false
      assert SessionStateChanged.session_state_changed?(nil) == false
      assert SessionStateChanged.session_state_changed?("string") == false
    end
  end
end
