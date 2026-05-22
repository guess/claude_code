defmodule ClaudeCode.Message.SystemMessage.MirrorErrorTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.MirrorError

  describe "new/1" do
    test "parses a valid mirror_error message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "mirror_error",
        "error" => "Connection refused",
        "key" => %{
          "project_key" => "proj_abc",
          "session_id" => "sess_xyz",
          "subpath" => "logs"
        },
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = MirrorError.new(json)
      assert message.type == :system
      assert message.subtype == :mirror_error
      assert message.error == "Connection refused"
      assert message.key == %{"project_key" => "proj_abc", "session_id" => "sess_xyz", "subpath" => "logs"}
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "handles absent optional key field" do
      json = %{
        "type" => "system",
        "subtype" => "mirror_error",
        "error" => "Something went wrong",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = MirrorError.new(json)
      assert message.key == nil
      assert message.uuid == nil
    end

    test "stores key as raw map" do
      json = %{
        "type" => "system",
        "subtype" => "mirror_error",
        "error" => "Failed",
        "key" => %{"project_key" => "proj_1", "session_id" => "sess_1"},
        "session_id" => "session-abc"
      }

      assert {:ok, message} = MirrorError.new(json)
      assert is_map(message.key)
      assert message.key["project_key"] == "proj_1"
      assert message.key["session_id"] == "sess_1"
    end

    test "returns error for missing required fields (error)" do
      json = %{"type" => "system", "subtype" => "mirror_error"}
      assert {:error, :missing_required_fields} = MirrorError.new(json)
    end

    test "returns error for missing session_id" do
      json = %{"type" => "system", "subtype" => "mirror_error", "error" => "some error"}
      assert {:error, :missing_required_fields} = MirrorError.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = MirrorError.new(json)
    end
  end

  describe "mirror_error?/1" do
    test "returns true for a MirrorError struct" do
      message = %MirrorError{
        type: :system,
        subtype: :mirror_error,
        error: "some error",
        session_id: "session-1"
      }

      assert MirrorError.mirror_error?(message) == true
    end

    test "returns false for other values" do
      assert MirrorError.mirror_error?(%{}) == false
      assert MirrorError.mirror_error?(nil) == false
      assert MirrorError.mirror_error?("string") == false
    end
  end
end
