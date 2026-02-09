defmodule ClaudeCode.StreamTest do
  use ExUnit.Case, async: true

  import ClaudeCode.Test.Factory

  alias ClaudeCode.Message
  alias ClaudeCode.Message.PartialAssistantMessage
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

  describe "tool_results_by_name/2" do
    test "extracts tool results matching tool name" do
      tool_id = "tool_123"

      messages = [
        assistant_message(
          message: %{
            content: [
              text_content("I'll read the file"),
              tool_use_content("Read", %{path: "/tmp/test.txt"}, tool_id)
            ]
          }
        ),
        user_message(
          message: %{
            content: [tool_result_content("file contents here", tool_id)]
          }
        )
      ]

      results = messages |> Stream.tool_results_by_name("Read") |> Enum.to_list()

      assert length(results) == 1
      assert hd(results).content == "file contents here"
      assert hd(results).tool_use_id == tool_id
    end

    test "filters out results from other tools" do
      read_id = "tool_read_123"
      bash_id = "tool_bash_456"

      messages = [
        assistant_message(
          message: %{
            content: [
              tool_use_content("Read", %{path: "/tmp/test.txt"}, read_id),
              tool_use_content("Bash", %{command: "ls"}, bash_id)
            ]
          }
        ),
        user_message(
          message: %{
            content: [
              tool_result_content("file contents", read_id),
              tool_result_content("file1.txt\nfile2.txt", bash_id)
            ]
          }
        )
      ]

      read_results = messages |> Stream.tool_results_by_name("Read") |> Enum.to_list()
      assert length(read_results) == 1
      assert hd(read_results).content == "file contents"

      bash_results = messages |> Stream.tool_results_by_name("Bash") |> Enum.to_list()
      assert length(bash_results) == 1
      assert hd(bash_results).content == "file1.txt\nfile2.txt"
    end

    test "handles multiple tool uses of same type" do
      id1 = "tool_read_1"
      id2 = "tool_read_2"

      messages = [
        assistant_message(
          message: %{
            content: [
              tool_use_content("Read", %{path: "/tmp/file1.txt"}, id1)
            ]
          }
        ),
        user_message(
          message: %{
            content: [tool_result_content("contents of file 1", id1)]
          }
        ),
        assistant_message(
          message: %{
            content: [
              tool_use_content("Read", %{path: "/tmp/file2.txt"}, id2)
            ]
          }
        ),
        user_message(
          message: %{
            content: [tool_result_content("contents of file 2", id2)]
          }
        )
      ]

      results = messages |> Stream.tool_results_by_name("Read") |> Enum.to_list()

      assert length(results) == 2
      assert Enum.at(results, 0).content == "contents of file 1"
      assert Enum.at(results, 1).content == "contents of file 2"
    end

    test "returns empty when no matching tool uses exist" do
      messages = [
        assistant_message(
          message: %{
            content: [
              tool_use_content("Bash", %{command: "ls"}, "tool_123")
            ]
          }
        ),
        user_message(
          message: %{
            content: [tool_result_content("file1.txt", "tool_123")]
          }
        )
      ]

      results = messages |> Stream.tool_results_by_name("Read") |> Enum.to_list()
      assert results == []
    end

    test "handles stream with no tool uses" do
      messages = [
        system_message(),
        assistant_message(message: %{content: [text_content("Just text")]}),
        result_message()
      ]

      results = messages |> Stream.tool_results_by_name("Read") |> Enum.to_list()
      assert results == []
    end

    test "ignores tool results without matching tool use" do
      # This simulates a malformed stream where result appears without prior tool use
      messages = [
        user_message(
          message: %{
            content: [tool_result_content("orphan result", "unknown_id")]
          }
        )
      ]

      results = messages |> Stream.tool_results_by_name("Read") |> Enum.to_list()
      assert results == []
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
      assert match?(%PartialAssistantMessage{event: %{type: :content_block_start}}, hd(starts))

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
      assert Enum.all?(stream_events, &match?(%PartialAssistantMessage{}, &1))
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
      assert Enum.all?(text_deltas, &PartialAssistantMessage.text_delta?/1)
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

  describe "final_text/1" do
    test "returns result text from stream" do
      messages = [
        system_message(),
        assistant_message(message: %{content: [text_content("Thinking...")]}),
        result_message(%{result: "The final answer is 42."})
      ]

      assert Stream.final_text(messages) == "The final answer is 42."
    end

    test "returns nil when no result message" do
      messages = [
        system_message(),
        assistant_message(message: %{content: [text_content("Hello")]})
      ]

      assert Stream.final_text(messages) == nil
    end

    test "returns first result when multiple exist" do
      messages = [
        result_message(%{result: "First result"}),
        result_message(%{result: "Second result"})
      ]

      assert Stream.final_text(messages) == "First result"
    end

    test "handles empty stream" do
      assert Stream.final_text([]) == nil
    end
  end

  describe "collect/1" do
    test "collects all content from stream" do
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
            content: [
              tool_use_content("Write", %{path: "test.txt"}, "tool_1")
            ]
          }
        ),
        user_message(
          message: %{
            content: [tool_result_content("File written successfully", "tool_1")]
          }
        ),
        result_message(%{result: "Operation complete."})
      ]

      summary = Stream.collect(messages)

      assert summary.text == "Hello world!"
      assert length(summary.tool_calls) == 1
      [{tool_use, tool_result}] = summary.tool_calls
      assert tool_use.name == "Write"
      assert tool_result.content == "File written successfully"
      assert summary.result == "Operation complete."
      assert summary.is_error == false
    end

    test "collects thinking content" do
      messages = [
        assistant_message(
          message: %{
            content: [
              thinking_content("Let me think..."),
              thinking_content(" Yes, I see."),
              text_content("Here's my answer.")
            ]
          }
        ),
        result_message(%{result: "Done"})
      ]

      summary = Stream.collect(messages)

      assert summary.thinking == "Let me think... Yes, I see."
      assert summary.text == "Here's my answer."
    end

    test "handles error results" do
      messages = [
        assistant_message(message: %{content: [text_content("Attempting...")]}),
        result_message(%{result: "Error: Something went wrong", is_error: true})
      ]

      summary = Stream.collect(messages)

      assert summary.is_error == true
      assert summary.result == "Error: Something went wrong"
    end

    test "handles empty stream" do
      summary = Stream.collect([])

      assert summary.text == ""
      assert summary.tool_calls == []
      assert summary.thinking == ""
      assert summary.result == nil
      assert summary.is_error == false
    end

    test "collects multiple tool calls with results" do
      messages = [
        assistant_message(
          message: %{
            content: [
              tool_use_content("Read", %{path: "a.txt"}, "tool_1"),
              tool_use_content("Read", %{path: "b.txt"}, "tool_2")
            ]
          }
        ),
        user_message(
          message: %{
            content: [
              tool_result_content("contents of a", "tool_1"),
              tool_result_content("contents of b", "tool_2")
            ]
          }
        ),
        assistant_message(
          message: %{
            content: [
              tool_use_content("Write", %{path: "c.txt"}, "tool_3")
            ]
          }
        ),
        user_message(
          message: %{
            content: [tool_result_content("written", "tool_3")]
          }
        )
      ]

      summary = Stream.collect(messages)

      assert length(summary.tool_calls) == 3
      assert Enum.map(summary.tool_calls, fn {use, _result} -> use.name end) == ["Read", "Read", "Write"]

      assert Enum.map(summary.tool_calls, fn {_use, result} -> result.content end) == [
               "contents of a",
               "contents of b",
               "written"
             ]
    end

    test "handles tool use without result" do
      messages = [
        assistant_message(
          message: %{
            content: [
              tool_use_content("Read", %{path: "a.txt"}, "tool_1")
            ]
          }
        )
        # No user message with tool result
      ]

      summary = Stream.collect(messages)

      assert length(summary.tool_calls) == 1
      [{tool_use, tool_result}] = summary.tool_calls
      assert tool_use.name == "Read"
      assert tool_result == nil
    end
  end

  describe "tap/1" do
    test "invokes callback for each message" do
      messages = [
        system_message(),
        assistant_message(),
        result_message()
      ]

      {:ok, agent} = Agent.start_link(fn -> [] end)

      messages
      |> Stream.tap(fn msg -> Agent.update(agent, fn msgs -> [msg | msgs] end) end)
      |> Enum.to_list()

      collected = Agent.get(agent, & &1)
      Agent.stop(agent)

      assert length(collected) == 3
    end

    test "passes messages through unchanged" do
      messages = [
        system_message(),
        assistant_message(message: %{content: [text_content("Hello")]}),
        result_message(%{result: "Done"})
      ]

      result =
        messages
        |> Stream.tap(fn _ -> :ignored end)
        |> Enum.to_list()

      assert result == messages
    end

    test "works in pipeline with other stream functions" do
      messages = [
        assistant_message(message: %{content: [text_content("Hello")]}),
        result_message(%{result: "World"})
      ]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      text =
        messages
        |> Stream.tap(fn _ -> Agent.update(agent, &(&1 + 1)) end)
        |> Stream.text_content()
        |> Enum.join()

      count = Agent.get(agent, & &1)
      Agent.stop(agent)

      assert text == "Hello"
      assert count == 2
    end
  end

  describe "on_tool_use/2" do
    test "invokes callback for each tool use" do
      messages = [
        assistant_message(
          message: %{
            content: [
              text_content("I'll read the files"),
              tool_use_content("Read", %{path: "a.txt"}, "tool_1"),
              tool_use_content("Read", %{path: "b.txt"}, "tool_2")
            ]
          }
        ),
        assistant_message(
          message: %{
            content: [
              tool_use_content("Write", %{path: "c.txt"}, "tool_3")
            ]
          }
        )
      ]

      {:ok, agent} = Agent.start_link(fn -> [] end)

      messages
      |> Stream.on_tool_use(fn tool -> Agent.update(agent, fn tools -> [tool.name | tools] end) end)
      |> Enum.to_list()

      tool_names = agent |> Agent.get(& &1) |> Enum.reverse()
      Agent.stop(agent)

      assert tool_names == ["Read", "Read", "Write"]
    end

    test "passes messages through unchanged" do
      messages = [
        assistant_message(
          message: %{
            content: [tool_use_content("Read", %{path: "test.txt"}, "tool_1")]
          }
        ),
        result_message(%{result: "Done"})
      ]

      result =
        messages
        |> Stream.on_tool_use(fn _ -> :ignored end)
        |> Enum.to_list()

      assert result == messages
    end

    test "does not invoke callback when no tool uses" do
      messages = [
        system_message(),
        assistant_message(message: %{content: [text_content("Just text")]}),
        result_message(%{result: "Done"})
      ]

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      messages
      |> Stream.on_tool_use(fn _ -> Agent.update(agent, &(&1 + 1)) end)
      |> Enum.to_list()

      count = Agent.get(agent, & &1)
      Agent.stop(agent)

      assert count == 0
    end

    test "works with final_text in pipeline" do
      messages = [
        assistant_message(
          message: %{
            content: [
              text_content("Creating file..."),
              tool_use_content("Write", %{path: "test.txt"}, "tool_1")
            ]
          }
        ),
        result_message(%{result: "File created successfully"})
      ]

      {:ok, agent} = Agent.start_link(fn -> [] end)

      result =
        messages
        |> Stream.on_tool_use(fn tool -> Agent.update(agent, fn t -> [tool.name | t] end) end)
        |> Stream.final_text()

      tools = Agent.get(agent, & &1)
      Agent.stop(agent)

      assert result == "File created successfully"
      assert tools == ["Write"]
    end
  end
end
