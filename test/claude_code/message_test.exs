defmodule ClaudeCode.MessageTest do
  use ExUnit.Case

  alias ClaudeCode.Message

  describe "from_json/1" do
    test "parses assistant message" do
      json = %{
        "type" => "assistant_message",
        "content" => "Hello, I'm Claude!",
        "id" => "msg_123"
      }

      message = Message.from_json(json)

      assert message.type == :assistant
      assert message.content == "Hello, I'm Claude!"
      assert message.metadata == %{"id" => "msg_123"}
    end

    test "parses error message" do
      json = %{
        "type" => "error",
        "message" => "Something went wrong",
        "code" => "ERR_001"
      }

      message = Message.from_json(json)

      assert message.type == :error
      assert message.content == "Something went wrong"
      assert message.metadata == %{"code" => "ERR_001"}
    end

    test "parses generic message type" do
      json = %{
        "type" => "tool_use",
        "content" => "Using a tool",
        "tool" => "calculator"
      }

      message = Message.from_json(json)

      assert message.type == :tool_use
      assert message.content == "Using a tool"
      assert message.metadata == %{"tool" => "calculator"}
    end

    test "handles missing content field" do
      json = %{
        "type" => "status",
        "status" => "ready"
      }

      message = Message.from_json(json)

      assert message.type == :status
      assert message.content == ""
      assert message.metadata == %{"status" => "ready"}
    end
  end

  describe "error?/1" do
    test "returns true for error messages" do
      message = %Message{type: :error, content: "Error", metadata: %{}}
      assert Message.error?(message)
    end

    test "returns false for non-error messages" do
      message = %Message{type: :assistant, content: "Hello", metadata: %{}}
      refute Message.error?(message)
    end
  end

  describe "assistant?/1" do
    test "returns true for assistant messages" do
      message = %Message{type: :assistant, content: "Hello", metadata: %{}}
      assert Message.assistant?(message)
    end

    test "returns false for non-assistant messages" do
      message = %Message{type: :error, content: "Error", metadata: %{}}
      refute Message.assistant?(message)
    end
  end
end
