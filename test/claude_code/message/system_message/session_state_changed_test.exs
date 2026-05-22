defmodule ClaudeCode.Message.SystemMessage.SessionStateChangedTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.SessionStateChanged

  describe "new/1" do
    test "parses a valid session_state_changed message with all fields" do
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

    test "parses state 'idle' to :idle" do
      assert {:ok, message} = SessionStateChanged.new(base_json("idle"))
      assert message.state == :idle
    end

    test "parses state 'running' to :running" do
      assert {:ok, message} = SessionStateChanged.new(base_json("running"))
      assert message.state == :running
    end

    test "parses state 'requires_action' to :requires_action" do
      assert {:ok, message} = SessionStateChanged.new(base_json("requires_action"))
      assert message.state == :requires_action
    end

    test "parses unknown state to nil" do
      assert {:ok, message} = SessionStateChanged.new(base_json("unknown_state"))
      assert message.state == nil
    end

    test "handles absent uuid" do
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

  defp base_json(state) do
    %{
      "type" => "system",
      "subtype" => "session_state_changed",
      "state" => state,
      "session_id" => "session-abc"
    }
  end
end
