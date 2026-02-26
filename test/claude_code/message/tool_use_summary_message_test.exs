defmodule ClaudeCode.Message.ToolUseSummaryMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.ToolUseSummaryMessage

  describe "new/1" do
    test "parses a valid tool use summary with tool IDs" do
      json = %{
        "type" => "tool_use_summary",
        "summary" => "Read 3 files and edited 1 file",
        "preceding_tool_use_ids" => ["toolu_abc", "toolu_def", "toolu_ghi"],
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ToolUseSummaryMessage.new(json)
      assert message.type == :tool_use_summary
      assert message.summary == "Read 3 files and edited 1 file"
      assert message.preceding_tool_use_ids == ["toolu_abc", "toolu_def", "toolu_ghi"]
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses tool use summary with empty tool IDs" do
      json = %{
        "type" => "tool_use_summary",
        "summary" => "No tools used",
        "preceding_tool_use_ids" => [],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ToolUseSummaryMessage.new(json)
      assert message.preceding_tool_use_ids == []
    end

    test "defaults preceding_tool_use_ids to empty list when missing" do
      json = %{
        "type" => "tool_use_summary",
        "summary" => "Some summary",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ToolUseSummaryMessage.new(json)
      assert message.preceding_tool_use_ids == []
    end

    test "returns error for missing required fields" do
      json = %{"type" => "tool_use_summary"}
      assert {:error, :missing_required_fields} = ToolUseSummaryMessage.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "result"}
      assert {:error, :invalid_message_type} = ToolUseSummaryMessage.new(json)
    end
  end
end
