defmodule ClaudeCode.StreamTest do
  use ExUnit.Case, async: true

  import ClaudeCode.Test.MessageFixtures

  alias ClaudeCode.Message
  alias ClaudeCode.Message.StreamEventMessage
  alias ClaudeCode.Stream

  describe "text_content/1" do
    test "extracts text from assistant messages" do
      messages = [
        system_message(),
        assistant_message(
          message: %{
            content: [
              text_content("Hello "),
              text_content("world!")
            ]
          }
        ),
        assistant_message(
          message: %{
            content: [text_content(" How are you?")]
          }
        ),
        result_message()
      ]

      text_stream = Stream.text_content(messages)
      assert Enum.to_list(text_stream) == ["Hello ", "world!", " How are you?"]
    end

    test "ignores non-text content" do
      messages = [
        assistant_message(
          message: %{
            content: [
              text_content("Here's a file: "),
              tool_use_content("write_file", %{path: "test.txt", content: "data"}),
              text_content(" Done!")
            ]
          }
        )
      ]

      text_stream = Stream.text_content(messages)
      assert Enum.to_list(text_stream) == ["Here's a file: ", " Done!"]
    end

    test "handles empty content" do
      messages = [
        assistant_message(message: %{content: []})
      ]

      text_stream = Stream.text_content(messages)
      assert Enum.to_list(text_stream) == []
    end
  end

  describe "thinking_content/1" do
    test "extracts thinking from assistant messages" do
      messages = [
        system_message(),
        assistant_message(
          message: %{
            content: [
              thinking_content("First reasoning step"),
              thinking_content("Second reasoning step")
            ]
          }
        ),
        assistant_message(
          message: %{
            content: [thinking_content("Third step")]
          }
        ),
        result_message()
      ]

      thinking_stream = Stream.thinking_content(messages)
      assert Enum.to_list(thinking_stream) == ["First reasoning step", "Second reasoning step", "Third step"]
    end

    test "ignores non-thinking content" do
      messages = [
        assistant_message(
          message: %{
            content: [
              thinking_content("I'm reasoning..."),
              text_content("Here's my answer"),
              tool_use_content("write_file", %{path: "test.txt", content: "data"})
            ]
          }
        )
      ]

      thinking_stream = Stream.thinking_content(messages)
      assert Enum.to_list(thinking_stream) == ["I'm reasoning..."]
    end

    test "handles empty content" do
      messages = [
        assistant_message(message: %{content: []})
      ]

      thinking_stream = Stream.thinking_content(messages)
      assert Enum.to_list(thinking_stream) == []
    end

    test "handles messages with no thinking content" do
      messages = [
        assistant_message(
          message: %{
            content: [text_content("Just text, no thinking")]
          }
        )
      ]

      thinking_stream = Stream.thinking_content(messages)
      assert Enum.to_list(thinking_stream) == []
    end
  end

  describe "tool_uses/1" do
    test "extracts tool use blocks" do
      messages = [
        assistant_message(
          message: %{
            content: [
              text_content("I'll create a file"),
              tool_use_content("write_file", %{path: "file1.txt", content: "data1"})
            ]
          }
        ),
        assistant_message(
          message: %{
            content: [
              tool_use_content("read_file", %{path: "file2.txt"})
            ]
          }
        )
      ]

      tool_uses = messages |> Stream.tool_uses() |> Enum.to_list()

      assert length(tool_uses) == 2
      assert Enum.at(tool_uses, 0).name == "write_file"
      assert Enum.at(tool_uses, 1).name == "read_file"
    end

    test "ignores messages without tool uses" do
      messages = [
        system_message(),
        assistant_message(message: %{content: [text_content("Just text")]}),
        result_message()
      ]

      tool_uses = messages |> Stream.tool_uses() |> Enum.to_list()
      assert tool_uses == []
    end
  end

  describe "filter_type/2" do
    test "filters by message type" do
      messages = [
        system_message(),
        assistant_message(),
        user_message(),
        result_message()
      ]

      assistant_only = messages |> Stream.filter_type(:assistant) |> Enum.to_list()
      assert length(assistant_only) == 1
      assert match?(%Message.AssistantMessage{}, hd(assistant_only))

      result_only = messages |> Stream.filter_type(:result) |> Enum.to_list()
      assert length(result_only) == 1
      assert match?(%Message.ResultMessage{}, hd(result_only))
    end

    test "filters tool_use pseudo-type" do
      messages = [
        assistant_message(
          message: %{
            content: [text_content("Hello")]
          }
        ),
        assistant_message(
          message: %{
            content: [
              tool_use_content("test", %{})
            ]
          }
        )
      ]

      tool_messages = messages |> Stream.filter_type(:tool_use) |> Enum.to_list()
      assert length(tool_messages) == 1
    end
  end

  describe "until_result/1" do
    test "stops at result message" do
      messages = [
        system_message(),
        assistant_message(),
        result_message(),
        # Should not be included
        assistant_message()
      ]

      truncated = messages |> Stream.until_result() |> Enum.to_list()

      # Should have system, assistant, and result (not the second assistant)
      assert length(truncated) == 3
      assert match?(%Message.SystemMessage{}, Enum.at(truncated, 0))
      assert match?(%Message.AssistantMessage{}, Enum.at(truncated, 1))
      assert match?(%Message.ResultMessage{}, Enum.at(truncated, 2))
    end

    test "includes all messages if no result" do
      messages = [
        system_message(),
        assistant_message()
      ]

      all_messages = messages |> Stream.until_result() |> Enum.to_list()
      assert length(all_messages) == 2
    end
  end

  describe "buffered_text/1" do
    test "buffers text until sentence boundaries" do
      messages = [
        assistant_message(
          message: %{
            content: [text_content("This is the first part")]
          }
        ),
        assistant_message(
          message: %{
            content: [text_content(" of a sentence. ")]
          }
        ),
        assistant_message(
          message: %{
            content: [text_content("This is another")]
          }
        ),
        assistant_message(
          message: %{
            content: [text_content(" sentence!")]
          }
        )
      ]

      buffered = messages |> Stream.buffered_text() |> Enum.to_list()
      assert buffered == ["This is the first part of a sentence. "]
    end

    test "flushes buffer on result message" do
      messages = [
        assistant_message(
          message: %{
            content: [text_content("Incomplete sentence")]
          }
        ),
        result_message()
      ]

      buffered = messages |> Stream.buffered_text() |> Enum.to_list()
      assert buffered == ["Incomplete sentence"]
    end

    test "handles multiple sentences in one message" do
      messages = [
        assistant_message(
          message: %{
            content: [text_content("First. Second. ")]
          }
        )
      ]

      buffered = messages |> Stream.buffered_text() |> Enum.to_list()
      assert buffered == ["First. Second. "]
    end
  end

  describe "text_deltas/1" do
    test "extracts text from text_delta stream events" do
      events = [
        stream_event_message_start(),
        stream_event_content_block_start(),
        stream_event_text_delta("Hello"),
        stream_event_text_delta(" "),
        stream_event_text_delta("World!"),
        stream_event_content_block_stop(),
        stream_event_message_stop()
      ]

      text_chunks = events |> Stream.text_deltas() |> Enum.to_list()
      assert text_chunks == ["Hello", " ", "World!"]
    end

    test "ignores non-text-delta events" do
      events = [
        stream_event_message_start(),
        stream_event_content_block_start(),
        stream_event_text_delta("Hello"),
        stream_event_input_json_delta("{\"path\":"),
        stream_event_text_delta(" World"),
        stream_event_content_block_stop()
      ]

      text_chunks = events |> Stream.text_deltas() |> Enum.to_list()
      assert text_chunks == ["Hello", " World"]
    end

    test "handles empty stream" do
      text_chunks = [] |> Stream.text_deltas() |> Enum.to_list()
      assert text_chunks == []
    end

    test "filters out non-stream-event messages" do
      events = [
        system_message(),
        stream_event_text_delta("Hello"),
        assistant_message(message: %{content: [text_content("world")]}),
        stream_event_text_delta(" there")
      ]

      text_chunks = events |> Stream.text_deltas() |> Enum.to_list()
      assert text_chunks == ["Hello", " there"]
    end
  end

  describe "thinking_deltas/1" do
    test "extracts thinking from thinking_delta stream events" do
      events = [
        stream_event_message_start(),
        stream_event_content_block_start(),
        stream_event_thinking_delta("Let me "),
        stream_event_thinking_delta("reason through "),
        stream_event_thinking_delta("this..."),
        stream_event_content_block_stop(),
        stream_event_message_stop()
      ]

      thinking_chunks = events |> Stream.thinking_deltas() |> Enum.to_list()
      assert thinking_chunks == ["Let me ", "reason through ", "this..."]
    end

    test "ignores non-thinking-delta events" do
      events = [
        stream_event_message_start(),
        stream_event_content_block_start(),
        stream_event_thinking_delta("Reasoning..."),
        stream_event_text_delta("Hello"),
        stream_event_thinking_delta(" more reasoning"),
        stream_event_content_block_stop()
      ]

      thinking_chunks = events |> Stream.thinking_deltas() |> Enum.to_list()
      assert thinking_chunks == ["Reasoning...", " more reasoning"]
    end

    test "handles empty stream" do
      thinking_chunks = [] |> Stream.thinking_deltas() |> Enum.to_list()
      assert thinking_chunks == []
    end

    test "filters out non-stream-event messages" do
      events = [
        system_message(),
        stream_event_thinking_delta("Reasoning"),
        assistant_message(message: %{content: [text_content("response")]}),
        stream_event_thinking_delta(" more")
      ]

      thinking_chunks = events |> Stream.thinking_deltas() |> Enum.to_list()
      assert thinking_chunks == ["Reasoning", " more"]
    end
  end

  describe "content_deltas/1" do
    test "extracts all content deltas with index" do
      events = [
        stream_event_content_block_start(%{index: 0}),
        stream_event_text_delta("Hello", %{index: 0}),
        stream_event_text_delta(" World", %{index: 0}),
        stream_event_content_block_stop(%{index: 0})
      ]

      deltas = events |> Stream.content_deltas() |> Enum.to_list()

      assert length(deltas) == 2
      assert Enum.at(deltas, 0) == %{type: :text_delta, text: "Hello", index: 0}
      assert Enum.at(deltas, 1) == %{type: :text_delta, text: " World", index: 0}
    end

    test "handles mixed content types" do
      events = [
        stream_event_text_delta("I'll read the file", %{index: 0}),
        stream_event_input_json_delta("{\"path\":", %{index: 1}),
        stream_event_input_json_delta("\"/test.txt\"}", %{index: 1})
      ]

      deltas = events |> Stream.content_deltas() |> Enum.to_list()

      assert length(deltas) == 3
      assert Enum.at(deltas, 0).type == :text_delta
      assert Enum.at(deltas, 0).index == 0
      assert Enum.at(deltas, 1).type == :input_json_delta
      assert Enum.at(deltas, 1).index == 1
      assert Enum.at(deltas, 2).type == :input_json_delta
    end

    test "ignores non-delta events" do
      events = [
        stream_event_message_start(),
        stream_event_content_block_start(),
        stream_event_text_delta("Hello"),
        stream_event_content_block_stop(),
        stream_event_message_stop()
      ]

      deltas = events |> Stream.content_deltas() |> Enum.to_list()

      assert length(deltas) == 1
      assert hd(deltas).text == "Hello"
    end
  end

  describe "filter_event_type/2" do
    test "filters by stream event type" do
      events = [
        stream_event_message_start(),
        stream_event_content_block_start(),
        stream_event_text_delta("Hello"),
        stream_event_content_block_stop(),
        stream_event_message_stop()
      ]

      starts = events |> Stream.filter_event_type(:content_block_start) |> Enum.to_list()
      assert length(starts) == 1
      assert match?(%StreamEventMessage{event: %{type: :content_block_start}}, hd(starts))

      deltas = events |> Stream.filter_event_type(:content_block_delta) |> Enum.to_list()
      assert length(deltas) == 1
    end

    test "handles mixed message types" do
      events = [
        system_message(),
        stream_event_text_delta("Hello"),
        assistant_message(),
        stream_event_message_stop()
      ]

      stops = events |> Stream.filter_event_type(:message_stop) |> Enum.to_list()
      assert length(stops) == 1
    end
  end

  describe "filter_type/2 with stream events" do
    test "filters stream_event type" do
      events = [
        system_message(),
        stream_event_text_delta("Hello"),
        assistant_message(),
        stream_event_message_stop(),
        result_message()
      ]

      stream_events = events |> Stream.filter_type(:stream_event) |> Enum.to_list()
      assert length(stream_events) == 2
      assert Enum.all?(stream_events, &match?(%StreamEventMessage{}, &1))
    end

    test "filters text_delta pseudo-type" do
      events = [
        stream_event_message_start(),
        stream_event_text_delta("Hello"),
        stream_event_input_json_delta("{}"),
        stream_event_text_delta(" World"),
        stream_event_message_stop()
      ]

      text_deltas = events |> Stream.filter_type(:text_delta) |> Enum.to_list()
      assert length(text_deltas) == 2
      assert Enum.all?(text_deltas, &StreamEventMessage.text_delta?/1)
    end
  end

  describe "stream_event_sequence/1 fixture" do
    test "creates a complete event sequence" do
      sequence = stream_event_sequence(["Hello", " ", "World!"])

      # message_start, block_start, 3 deltas, block_stop, message_delta, message_stop
      assert length(sequence) == 8

      text_chunks = sequence |> Stream.text_deltas() |> Enum.to_list()
      assert text_chunks == ["Hello", " ", "World!"]
    end
  end
end
