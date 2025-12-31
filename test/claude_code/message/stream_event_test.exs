defmodule ClaudeCode.Message.StreamEventTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message
  alias ClaudeCode.Message.StreamEvent

  describe "new/1" do
    test "parses a text_delta stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "text_delta", "text" => "Hello"}
        },
        "session_id" => "test-123",
        "parent_tool_use_id" => nil,
        "uuid" => "uuid-456"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.type == :stream_event
      assert event.event.type == :content_block_delta
      assert event.event.index == 0
      assert event.event.delta.type == :text_delta
      assert event.event.delta.text == "Hello"
      assert event.session_id == "test-123"
      assert event.uuid == "uuid-456"
    end

    test "parses a message_start stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "message_start",
          "message" => %{"model" => "claude-3", "id" => "msg_123"}
        },
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.type == :message_start
      assert event.event.message.model == "claude-3"
      assert event.event.message.id == "msg_123"
    end

    test "parses a content_block_start stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_start",
          "index" => 0,
          "content_block" => %{"type" => "text", "text" => ""}
        },
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.type == :content_block_start
      assert event.event.index == 0
      assert event.event.content_block.type == :text
    end

    test "parses an input_json_delta stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_delta",
          "index" => 1,
          "delta" => %{"type" => "input_json_delta", "partial_json" => "{\"path\":"}
        },
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.delta.type == :input_json_delta
      assert event.event.delta.partial_json == "{\"path\":"
    end

    test "parses a thinking_delta stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "thinking_delta", "thinking" => "Let me reason through this..."}
        },
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.delta.type == :thinking_delta
      assert event.event.delta.thinking == "Let me reason through this..."
    end

    test "parses a content_block_stop stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_stop",
          "index" => 0
        },
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.type == :content_block_stop
      assert event.event.index == 0
    end

    test "parses a message_delta stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "message_delta",
          "delta" => %{"stop_reason" => "end_turn"},
          "usage" => %{"output_tokens" => 50}
        },
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.type == :message_delta
      assert event.event.usage.output_tokens == 50
    end

    test "parses a message_stop stream event" do
      json = %{
        "type" => "stream_event",
        "event" => %{"type" => "message_stop"},
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.type == :message_stop
    end

    test "parses tool_use content block start" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_start",
          "index" => 1,
          "content_block" => %{
            "type" => "tool_use",
            "id" => "tool_123",
            "name" => "read_file",
            "input" => %{}
          }
        },
        "session_id" => "test-123"
      }

      assert {:ok, event} = StreamEvent.new(json)
      assert event.event.content_block.type == :tool_use
      assert event.event.content_block.name == "read_file"
    end

    test "returns error for missing event" do
      json = %{
        "type" => "stream_event",
        "session_id" => "test-123"
      }

      assert {:error, :missing_event} = StreamEvent.new(json)
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "stream_event",
        "event" => %{"type" => "message_stop"}
      }

      assert {:error, :missing_session_id} = StreamEvent.new(json)
    end

    test "returns error for wrong type" do
      json = %{
        "type" => "assistant",
        "message" => %{}
      }

      assert {:error, :invalid_message_type} = StreamEvent.new(json)
    end
  end

  describe "Message.parse/1 integration" do
    test "parses stream_event type" do
      json = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "text_delta", "text" => "Hello"}
        },
        "session_id" => "test-123"
      }

      assert {:ok, %StreamEvent{}} = Message.parse(json)
    end
  end

  describe "helper functions" do
    test "text_delta?/1 returns true for text deltas" do
      event = build_event(:content_block_delta, %{type: :text_delta, text: "Hi"})
      assert StreamEvent.text_delta?(event)
    end

    test "text_delta?/1 returns false for non-text deltas" do
      event = build_event(:content_block_delta, %{type: :input_json_delta, partial_json: "{}"})
      refute StreamEvent.text_delta?(event)
    end

    test "get_text/1 extracts text from text delta" do
      event = build_event(:content_block_delta, %{type: :text_delta, text: "Hello World"})
      assert StreamEvent.get_text(event) == "Hello World"
    end

    test "get_text/1 returns nil for non-text delta" do
      event = build_event(:message_start, nil)
      assert StreamEvent.get_text(event) == nil
    end

    test "thinking_delta?/1 returns true for thinking deltas" do
      event = build_event(:content_block_delta, %{type: :thinking_delta, thinking: "reasoning"})
      assert StreamEvent.thinking_delta?(event)
    end

    test "thinking_delta?/1 returns false for non-thinking deltas" do
      event = build_event(:content_block_delta, %{type: :text_delta, text: "Hello"})
      refute StreamEvent.thinking_delta?(event)
    end

    test "get_thinking/1 extracts thinking from thinking delta" do
      event = build_event(:content_block_delta, %{type: :thinking_delta, thinking: "Let me think..."})
      assert StreamEvent.get_thinking(event) == "Let me think..."
    end

    test "get_thinking/1 returns nil for non-thinking delta" do
      event = build_event(:content_block_delta, %{type: :text_delta, text: "Hello"})
      assert StreamEvent.get_thinking(event) == nil
    end

    test "input_json_delta?/1 detects input_json_delta events" do
      event = build_event(:content_block_delta, %{type: :input_json_delta, partial_json: "{}"})
      assert StreamEvent.input_json_delta?(event)
    end

    test "get_partial_json/1 extracts partial JSON" do
      event = build_event(:content_block_delta, %{type: :input_json_delta, partial_json: "{\"path\":"})
      assert StreamEvent.get_partial_json(event) == "{\"path\":"
    end

    test "get_index/1 returns content block index" do
      event = build_event(:content_block_delta, %{type: :text_delta, text: "Hi"}, 2)
      assert StreamEvent.get_index(event) == 2
    end

    test "event_type/1 returns the event type" do
      event = build_event(:message_start, nil)
      assert StreamEvent.event_type(event) == :message_start
    end

    test "stream_event?/1 type guard" do
      event = build_event(:message_start, nil)
      assert StreamEvent.stream_event?(event)
      refute StreamEvent.stream_event?(%{type: "other"})
    end
  end

  # Helper to build stream events for testing
  defp build_event(event_type, delta, index \\ 0) do
    event =
      case event_type do
        :content_block_delta ->
          %{type: :content_block_delta, index: index, delta: delta}

        :message_start ->
          %{type: :message_start, message: %{}}

        type ->
          %{type: type}
      end

    %StreamEvent{
      type: :stream_event,
      event: event,
      session_id: "test-123"
    }
  end
end
