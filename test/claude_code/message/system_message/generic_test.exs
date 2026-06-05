defmodule ClaudeCode.Message.SystemMessage.GenericTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.SystemMessage.Generic

  doctest Generic

  describe "new/1" do
    test "parses an unknown system subtype, preserving the payload" do
      json = %{
        "type" => "system",
        "subtype" => "thinking_tokens",
        "session_id" => "session-abc",
        "uuid" => "uuid-123",
        "max_thinking_tokens" => 10_000
      }

      assert {:ok, message} = Generic.new(json)
      assert message.type == :system
      assert message.subtype == "thinking_tokens"
      assert message.session_id == "session-abc"
      assert message.uuid == "uuid-123"
      assert message.data == %{"max_thinking_tokens" => 10_000}
    end

    test "keeps subtype as a string rather than an atom" do
      json = %{"type" => "system", "subtype" => "thinking_tokens"}

      assert {:ok, message} = Generic.new(json)
      assert is_binary(message.subtype)
    end

    test "handles missing optional fields" do
      json = %{"type" => "system", "subtype" => "thinking_tokens"}

      assert {:ok, message} = Generic.new(json)
      assert message.session_id == nil
      assert message.uuid == nil
      assert message.data == %{}
    end

    test "returns error for a non-binary subtype" do
      json = %{"type" => "system", "subtype" => 123}
      assert {:error, :invalid_message_type} = Generic.new(json)
    end

    test "returns error for a non-system type" do
      json = %{"type" => "assistant", "subtype" => "thinking_tokens"}
      assert {:error, :invalid_message_type} = Generic.new(json)
    end
  end

  describe "generic?/1" do
    test "returns true for a Generic struct" do
      assert Generic.generic?(%Generic{type: :system, subtype: "thinking_tokens"}) == true
    end

    test "returns false for other values" do
      assert Generic.generic?(%{}) == false
      assert Generic.generic?(nil) == false
      assert Generic.generic?("string") == false
    end
  end

  describe "system-message family enrollment" do
    setup do
      {:ok, message} =
        Generic.new(%{
          "type" => "system",
          "subtype" => "thinking_tokens",
          "session_id" => "session-abc"
        })

      %{message: message}
    end

    test "SystemMessage.type?/1 recognizes a Generic message", %{message: message} do
      assert SystemMessage.type?(message) == true
    end

    test "Message.message?/1 recognizes a Generic message", %{message: message} do
      assert Message.message?(message) == true
    end
  end
end
