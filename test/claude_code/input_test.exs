defmodule ClaudeCode.InputTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Input

  describe "user_message/3" do
    test "builds basic user message with defaults" do
      json = Input.user_message("Hello, Claude!")

      decoded = Jason.decode!(json)

      assert decoded["type"] == "user"
      assert decoded["message"]["role"] == "user"
      assert decoded["message"]["content"] == "Hello, Claude!"
      assert decoded["session_id"] == "default"
      assert decoded["parent_tool_use_id"] == nil
    end

    test "builds user message with custom session ID" do
      json = Input.user_message("Hello!", "my-session-123")

      decoded = Jason.decode!(json)

      assert decoded["session_id"] == "my-session-123"
    end

    test "builds user message with parent_tool_use_id" do
      json = Input.user_message("Result", "session-456", parent_tool_use_id: "tool-789")

      decoded = Jason.decode!(json)

      assert decoded["parent_tool_use_id"] == "tool-789"
    end

    test "produces valid NDJSON line" do
      json = Input.user_message("Test message")

      # Should be a single line (no newlines)
      refute String.contains?(json, "\n")

      # Should be valid JSON
      assert {:ok, _} = Jason.decode(json)
    end
  end

  describe "tool_response/4" do
    test "builds tool response with string result" do
      json = Input.tool_response("tool-123", "File created successfully", "session-456")

      decoded = Jason.decode!(json)

      assert decoded["type"] == "user"
      assert decoded["message"]["role"] == "user"
      assert decoded["session_id"] == "session-456"
      assert decoded["parent_tool_use_id"] == "tool-123"

      [tool_result] = decoded["message"]["content"]
      assert tool_result["type"] == "tool_result"
      assert tool_result["tool_use_id"] == "tool-123"
      assert tool_result["content"] == "File created successfully"
      assert tool_result["is_error"] == false
    end

    test "builds tool response with map result" do
      result = %{"status" => "success", "data" => [1, 2, 3]}
      json = Input.tool_response("tool-abc", result, "session-def")

      decoded = Jason.decode!(json)

      [tool_result] = decoded["message"]["content"]
      # Map results are encoded as JSON strings
      assert tool_result["content"] == Jason.encode!(result)
    end

    test "builds tool response with error flag" do
      json = Input.tool_response("tool-err", "Something went wrong", "session-xyz", is_error: true)

      decoded = Jason.decode!(json)

      [tool_result] = decoded["message"]["content"]
      assert tool_result["is_error"] == true
    end

    test "produces valid NDJSON line" do
      json = Input.tool_response("tool-123", "result", "session-456")

      # Should be a single line (no newlines)
      refute String.contains?(json, "\n")

      # Should be valid JSON
      assert {:ok, _} = Jason.decode(json)
    end
  end
end
