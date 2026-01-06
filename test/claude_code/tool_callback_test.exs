defmodule ClaudeCode.ToolCallbackTest do
  use ExUnit.Case

  alias ClaudeCode.Content.ToolResult
  alias ClaudeCode.Content.ToolUse
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.UserMessage
  alias ClaudeCode.ToolCallback

  describe "process_message/3" do
    test "stores pending tool uses from Assistant messages" do
      tool_use = %ToolUse{type: :tool_use, id: "tool_123", name: "Read", input: %{"path" => "/tmp/file"}}

      message = %AssistantMessage{
        type: :assistant,
        session_id: "session_1",
        message: %{content: [tool_use]}
      }

      {pending, events} = ToolCallback.process_message(message, %{}, nil)

      assert Map.has_key?(pending, "tool_123")
      assert pending["tool_123"].name == "Read"
      assert pending["tool_123"].input == %{"path" => "/tmp/file"}
      assert events == []
    end

    test "stores multiple tool uses from single Assistant message" do
      tool_use1 = %ToolUse{type: :tool_use, id: "tool_1", name: "Read", input: %{"path" => "/a"}}
      tool_use2 = %ToolUse{type: :tool_use, id: "tool_2", name: "Write", input: %{"path" => "/b"}}

      message = %AssistantMessage{
        type: :assistant,
        session_id: "session_1",
        message: %{content: [tool_use1, tool_use2]}
      }

      {pending, events} = ToolCallback.process_message(message, %{}, nil)

      assert Map.has_key?(pending, "tool_1")
      assert Map.has_key?(pending, "tool_2")
      assert pending["tool_1"].name == "Read"
      assert pending["tool_2"].name == "Write"
      assert events == []
    end

    test "invokes callback when tool result arrives" do
      # Setup: pre-populate pending tools
      pending = %{
        "tool_123" => %{name: "Read", input: %{"path" => "/tmp"}, started_at: DateTime.utc_now()}
      }

      tool_result = %ToolResult{
        type: :tool_result,
        tool_use_id: "tool_123",
        content: "file contents",
        is_error: false
      }

      message = %UserMessage{
        type: :user,
        session_id: "session_1",
        message: %{content: [tool_result]}
      }

      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end

      {new_pending, events} = ToolCallback.process_message(message, pending, callback)

      # Tool should be removed from pending
      refute Map.has_key?(new_pending, "tool_123")

      # Event should be returned
      assert length(events) == 1
      event = hd(events)
      assert event.name == "Read"
      assert event.result == "file contents"
      assert event.is_error == false
      assert event.tool_use_id == "tool_123"

      # Wait for async callback
      assert_receive {:callback, received_event}, 100
      assert received_event.name == "Read"
      assert received_event.result == "file contents"
    end

    test "handles error results" do
      pending = %{
        "tool_456" => %{name: "Write", input: %{"path" => "/etc/passwd"}, started_at: DateTime.utc_now()}
      }

      tool_result = %ToolResult{
        type: :tool_result,
        tool_use_id: "tool_456",
        content: "Permission denied",
        is_error: true
      }

      message = %UserMessage{
        type: :user,
        session_id: "session_1",
        message: %{content: [tool_result]}
      }

      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end

      {_pending, events} = ToolCallback.process_message(message, pending, callback)

      assert length(events) == 1
      event = hd(events)
      assert event.is_error == true
      assert event.result == "Permission denied"

      assert_receive {:callback, received_event}, 100
      assert received_event.is_error == true
    end

    test "handles multiple tool results in single User message" do
      pending = %{
        "tool_1" => %{name: "Read", input: %{"path" => "/a"}, started_at: DateTime.utc_now()},
        "tool_2" => %{name: "Write", input: %{"path" => "/b"}, started_at: DateTime.utc_now()}
      }

      result1 = %ToolResult{type: :tool_result, tool_use_id: "tool_1", content: "ok1", is_error: false}
      result2 = %ToolResult{type: :tool_result, tool_use_id: "tool_2", content: "ok2", is_error: false}

      message = %UserMessage{
        type: :user,
        session_id: "session_1",
        message: %{content: [result1, result2]}
      }

      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end

      {new_pending, events} = ToolCallback.process_message(message, pending, callback)

      # Both should be removed from pending
      assert new_pending == %{}

      # Both events should be returned
      assert length(events) == 2

      # Should receive both callbacks
      assert_receive {:callback, _}, 100
      assert_receive {:callback, _}, 100
    end

    test "ignores tool results with no matching tool use" do
      # No pending tools
      pending = %{}

      tool_result = %ToolResult{
        type: :tool_result,
        tool_use_id: "unknown_tool",
        content: "result",
        is_error: false
      }

      message = %UserMessage{
        type: :user,
        session_id: "session_1",
        message: %{content: [tool_result]}
      }

      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end

      {new_pending, events} = ToolCallback.process_message(message, pending, callback)

      # No changes
      assert new_pending == %{}
      assert events == []

      # No callback should fire
      refute_receive {:callback, _}, 50
    end

    test "does nothing when no callback configured" do
      pending = %{
        "tool_123" => %{name: "Read", input: %{}, started_at: DateTime.utc_now()}
      }

      tool_result = %ToolResult{
        type: :tool_result,
        tool_use_id: "tool_123",
        content: "ok",
        is_error: false
      }

      message = %UserMessage{type: :user, session_id: "s1", message: %{content: [tool_result]}}

      {new_pending, events} = ToolCallback.process_message(message, pending, nil)

      # Still removes from pending to prevent memory leak
      assert new_pending == %{}
      assert events == []
    end

    test "passes through System messages unchanged" do
      message = %SystemMessage{
        type: :system,
        subtype: "init",
        uuid: "550e8400-e29b-41d4-a716-446655440000",
        session_id: "s1",
        model: "claude-3",
        cwd: "/test",
        tools: [],
        mcp_servers: [],
        permission_mode: "auto",
        api_key_source: "env",
        slash_commands: [],
        output_style: "default"
      }

      pending = %{"tool_1" => %{name: "Read", input: %{}, started_at: DateTime.utc_now()}}
      callback = fn _event -> :ok end

      {new_pending, events} = ToolCallback.process_message(message, pending, callback)

      # Pending should be unchanged
      assert new_pending == pending
      assert events == []
    end

    test "passes through Result messages unchanged" do
      message = %ResultMessage{
        type: :result,
        subtype: :success,
        is_error: false,
        result: "Done",
        session_id: "s1",
        duration_ms: 100,
        duration_api_ms: 80,
        num_turns: 1,
        total_cost_usd: 0.001,
        usage: %{}
      }

      pending = %{"tool_1" => %{name: "Read", input: %{}, started_at: DateTime.utc_now()}}
      callback = fn _event -> :ok end

      {new_pending, events} = ToolCallback.process_message(message, pending, callback)

      # Pending should be unchanged
      assert new_pending == pending
      assert events == []
    end

    test "event includes timestamp" do
      pending = %{
        "tool_123" => %{name: "Read", input: %{}, started_at: DateTime.utc_now()}
      }

      tool_result = %ToolResult{
        type: :tool_result,
        tool_use_id: "tool_123",
        content: "ok",
        is_error: false
      }

      message = %UserMessage{type: :user, session_id: "s1", message: %{content: [tool_result]}}

      test_pid = self()
      callback = fn event -> send(test_pid, {:callback, event}) end

      ToolCallback.process_message(message, pending, callback)

      assert_receive {:callback, event}, 100
      assert %DateTime{} = event.timestamp
    end
  end
end
