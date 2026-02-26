defmodule ClaudeCode.Message.PromptSuggestionMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.PromptSuggestionMessage

  describe "new/1" do
    test "parses a valid prompt suggestion message" do
      json = %{
        "type" => "prompt_suggestion",
        "suggestion" => "Now add tests for the new function",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = PromptSuggestionMessage.new(json)
      assert message.type == :prompt_suggestion
      assert message.suggestion == "Now add tests for the new function"
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses prompt suggestion without uuid" do
      json = %{
        "type" => "prompt_suggestion",
        "suggestion" => "Run the test suite",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = PromptSuggestionMessage.new(json)
      assert message.suggestion == "Run the test suite"
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "prompt_suggestion"}
      assert {:error, :missing_required_fields} = PromptSuggestionMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = PromptSuggestionMessage.new(json)
    end
  end
end
