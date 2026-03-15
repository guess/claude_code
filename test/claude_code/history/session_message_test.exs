defmodule ClaudeCode.History.SessionMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.History.SessionMessage

  @moduletag :history

  describe "from_entry/1" do
    test "parses user entry with string content" do
      entry = %{
        "type" => "user",
        "uuid" => "u1",
        "sessionId" => "session-123",
        "message" => %{"role" => "user", "content" => "Hello world"}
      }

      msg = SessionMessage.from_entry(entry)
      assert %SessionMessage{} = msg
      assert msg.type == :user
      assert msg.uuid == "u1"
      assert msg.session_id == "session-123"
      assert msg.message == %{content: "Hello world", role: :user}
      assert is_nil(msg.parent_tool_use_id)
    end

    test "parses user entry with content block list" do
      entry = %{
        "type" => "user",
        "uuid" => "u1",
        "sessionId" => "session-123",
        "message" => %{
          "role" => "user",
          "content" => [
            %{"type" => "tool_result", "tool_use_id" => "t1", "content" => "done"}
          ]
        }
      }

      msg = SessionMessage.from_entry(entry)
      assert [%ToolResultBlock{tool_use_id: "t1", content: "done"}] = msg.message.content
    end

    test "parses assistant entry with text blocks" do
      entry = %{
        "type" => "assistant",
        "uuid" => "a1",
        "sessionId" => "session-123",
        "message" => %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "Hi there!"}],
          "model" => "claude-3",
          "id" => "msg_1"
        }
      }

      msg = SessionMessage.from_entry(entry)
      assert msg.type == :assistant
      assert msg.uuid == "a1"
      assert [%TextBlock{text: "Hi there!"}] = msg.message.content
      assert msg.message.model == "claude-3"
    end

    test "parses assistant entry with tool use" do
      entry = %{
        "type" => "assistant",
        "uuid" => "a1",
        "sessionId" => "session-123",
        "message" => %{
          "role" => "assistant",
          "content" => [
            %{"type" => "tool_use", "id" => "tu1", "name" => "Bash", "input" => %{"command" => "ls"}}
          ],
          "model" => "claude-3",
          "id" => "msg_1"
        }
      }

      msg = SessionMessage.from_entry(entry)
      assert [%ToolUseBlock{name: "Bash", input: %{"command" => "ls"}}] = msg.message.content
    end

    test "preserves parentToolUseId" do
      entry = %{
        "type" => "user",
        "uuid" => "u1",
        "sessionId" => "session-123",
        "parentToolUseId" => "tu-parent",
        "message" => %{"role" => "user", "content" => "test"}
      }

      msg = SessionMessage.from_entry(entry)
      assert msg.parent_tool_use_id == "tu-parent"
    end

    test "handles nil message gracefully" do
      entry = %{
        "type" => "user",
        "uuid" => "u1",
        "sessionId" => "session-123",
        "message" => nil
      }

      msg = SessionMessage.from_entry(entry)
      assert msg.type == :user
      assert is_nil(msg.message)
    end

    test "handles missing fields with defaults" do
      entry = %{
        "type" => "assistant",
        "message" => %{"content" => [%{"type" => "text", "text" => "Hi"}]}
      }

      msg = SessionMessage.from_entry(entry)
      assert msg.uuid == ""
      assert msg.session_id == ""
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON with nil values stripped" do
      msg = %SessionMessage{
        type: :user,
        uuid: "u1",
        session_id: "s1",
        message: %{content: "Hello", role: :user},
        parent_tool_use_id: nil
      }

      {:ok, json} = Jason.encode(msg)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "user"
      assert decoded["uuid"] == "u1"
      refute Map.has_key?(decoded, "parent_tool_use_id")
    end
  end
end
