defmodule ClaudeCode.TestTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.UserMessage

  # ============================================================================
  # Message Builder Tests
  # ============================================================================

  describe "text/2" do
    test "creates assistant message with text content" do
      msg = ClaudeCode.Test.text("Hello world")

      assert %AssistantMessage{} = msg
      assert msg.type == :assistant
      assert [%Content.TextBlock{text: "Hello world"}] = msg.message.content
    end

    test "accepts custom options" do
      msg = ClaudeCode.Test.text("Hello", session_id: "custom-123", stop_reason: :end_turn)

      assert msg.session_id == "custom-123"
      assert msg.message.stop_reason == :end_turn
    end
  end

  describe "tool_use/1" do
    test "creates assistant message with tool use block" do
      msg = ClaudeCode.Test.tool_use(name: "Read", input: %{path: "/tmp/file.txt"})

      assert %AssistantMessage{} = msg

      assert [%Content.ToolUseBlock{name: "Read", input: %{path: "/tmp/file.txt"}}] =
               msg.message.content

      assert msg.message.stop_reason == :tool_use
    end

    test "accepts optional text before tool use" do
      msg =
        ClaudeCode.Test.tool_use(
          name: "Read",
          input: %{path: "/tmp/file.txt"},
          text: "Let me read that"
        )

      assert [%Content.TextBlock{text: "Let me read that"}, %Content.ToolUseBlock{}] =
               msg.message.content
    end

    test "accepts custom tool ID" do
      msg = ClaudeCode.Test.tool_use(name: "Read", input: %{}, id: "custom_tool_123")

      assert [%Content.ToolUseBlock{id: "custom_tool_123"}] = msg.message.content
    end
  end

  describe "tool_result/1" do
    test "creates user message with tool result block" do
      msg = ClaudeCode.Test.tool_result(content: "file contents")

      assert %UserMessage{} = msg

      assert [%Content.ToolResultBlock{content: "file contents", is_error: false}] =
               msg.message.content
    end

    test "supports error results" do
      msg = ClaudeCode.Test.tool_result(content: "Permission denied", is_error: true)

      assert [%Content.ToolResultBlock{is_error: true}] = msg.message.content
    end

    test "accepts custom tool_use_id" do
      msg = ClaudeCode.Test.tool_result(content: "result", tool_use_id: "custom_tool_123")

      assert [%Content.ToolResultBlock{tool_use_id: "custom_tool_123"}] = msg.message.content
    end
  end

  describe "thinking/1" do
    test "creates assistant message with thinking block" do
      msg = ClaudeCode.Test.thinking(thinking: "Let me analyze this...")

      assert %AssistantMessage{} = msg
      assert [%Content.ThinkingBlock{thinking: "Let me analyze this..."}] = msg.message.content
    end

    test "accepts optional text after thinking" do
      msg = ClaudeCode.Test.thinking(thinking: "Analyzing...", text: "Here's my answer")

      assert [%Content.ThinkingBlock{}, %Content.TextBlock{text: "Here's my answer"}] =
               msg.message.content
    end
  end

  describe "result/1" do
    test "creates success result by default" do
      msg = ClaudeCode.Test.result()

      assert %ResultMessage{} = msg
      assert msg.result == "Done"
      assert msg.is_error == false
      assert msg.subtype == :success
    end

    test "creates error result" do
      msg = ClaudeCode.Test.result(is_error: true, result: "Rate limit exceeded")

      assert msg.is_error == true
      assert msg.result == "Rate limit exceeded"
      assert msg.subtype == :error_during_execution
    end

    test "accepts custom subtype" do
      msg = ClaudeCode.Test.result(is_error: true, subtype: :error_max_turns)

      assert msg.subtype == :error_max_turns
    end
  end

  describe "system/1" do
    test "creates system initialization message" do
      msg = ClaudeCode.Test.system()

      assert %SystemMessage{} = msg
      assert msg.type == :system
      assert msg.subtype == :init
    end

    test "accepts custom options" do
      msg = ClaudeCode.Test.system(model: "claude-opus-4", tools: ["Read", "Edit"])

      assert msg.model == "claude-opus-4"
      assert msg.tools == ["Read", "Edit"]
    end
  end

  # ============================================================================
  # Stub Registration Tests
  # ============================================================================

  describe "stub/2" do
    test "registers a function stub" do
      ClaudeCode.Test.stub(TestStub1, fn query, _opts ->
        [ClaudeCode.Test.text("Response to: #{query}")]
      end)

      # Verify stub is retrievable via adapter
      messages = TestStub1 |> ClaudeCode.Test.stream("Hello", []) |> Enum.to_list()

      # Should have system, text, result (smart defaults)
      assert length(messages) == 3
      assert %SystemMessage{} = Enum.at(messages, 0)
      assert %AssistantMessage{} = Enum.at(messages, 1)
      assert %ResultMessage{} = Enum.at(messages, 2)
    end

    test "registers a static message list" do
      ClaudeCode.Test.stub(TestStub2, [
        ClaudeCode.Test.text("Static response")
      ])

      messages = TestStub2 |> ClaudeCode.Test.stream("anything", []) |> Enum.to_list()

      assert length(messages) == 3
    end
  end

  describe "stream/3" do
    test "raises when no stub is registered" do
      assert_raise RuntimeError, ~r/no stub found/, fn ->
        UnregisteredStub |> ClaudeCode.Test.stream("query", []) |> Enum.to_list()
      end
    end
  end

  # ============================================================================
  # Smart Defaults Tests
  # ============================================================================

  describe "stream building smart defaults" do
    test "auto-prepends system message if missing" do
      ClaudeCode.Test.stub(AutoSystemStub, [
        ClaudeCode.Test.text("Hello")
      ])

      messages = AutoSystemStub |> ClaudeCode.Test.stream("q", []) |> Enum.to_list()

      assert %SystemMessage{} = hd(messages)
    end

    test "does not duplicate system message if present" do
      ClaudeCode.Test.stub(ExplicitSystemStub, [
        ClaudeCode.Test.system(),
        ClaudeCode.Test.text("Hello")
      ])

      messages = ExplicitSystemStub |> ClaudeCode.Test.stream("q", []) |> Enum.to_list()

      system_count = Enum.count(messages, &match?(%SystemMessage{}, &1))
      assert system_count == 1
    end

    test "auto-appends result message if missing" do
      ClaudeCode.Test.stub(AutoResultStub, [
        ClaudeCode.Test.text("Final answer")
      ])

      messages = AutoResultStub |> ClaudeCode.Test.stream("q", []) |> Enum.to_list()

      assert %ResultMessage{result: "Final answer"} = List.last(messages)
    end

    test "does not duplicate result message if present" do
      ClaudeCode.Test.stub(ExplicitResultStub, [
        ClaudeCode.Test.text("Hello"),
        ClaudeCode.Test.result(result: "Custom result")
      ])

      messages = ExplicitResultStub |> ClaudeCode.Test.stream("q", []) |> Enum.to_list()

      result_count = Enum.count(messages, &match?(%ResultMessage{}, &1))
      assert result_count == 1
      assert %ResultMessage{result: "Custom result"} = List.last(messages)
    end

    test "auto-links tool_use IDs to tool_result messages" do
      ClaudeCode.Test.stub(ToolLinkStub, [
        ClaudeCode.Test.tool_use(name: "Read", input: %{path: "/tmp/x"}, id: "tool_abc"),
        ClaudeCode.Test.tool_result(content: "file contents")
      ])

      messages = ToolLinkStub |> ClaudeCode.Test.stream("q", []) |> Enum.to_list()

      # Find the tool_result message
      tool_result = Enum.find(messages, &match?(%UserMessage{}, &1))
      assert [%Content.ToolResultBlock{tool_use_id: "tool_abc"}] = tool_result.message.content
    end

    test "unifies session IDs across all messages" do
      ClaudeCode.Test.stub(SessionIdStub, [
        ClaudeCode.Test.text("Hello", session_id: "different-1"),
        ClaudeCode.Test.text("World", session_id: "different-2")
      ])

      messages = SessionIdStub |> ClaudeCode.Test.stream("q", session_id: "unified") |> Enum.to_list()

      session_ids = messages |> Enum.map(& &1.session_id) |> Enum.uniq()
      assert length(session_ids) == 1
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration with ClaudeCode.Session" do
    test "session uses adapter for queries" do
      ClaudeCode.Test.stub(SessionTestStub, fn query, _opts ->
        [
          ClaudeCode.Test.text("You asked: #{query}"),
          ClaudeCode.Test.result(result: "You asked: #{query}")
        ]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, SessionTestStub})

      result =
        session
        |> ClaudeCode.stream("Hello Claude!")
        |> ClaudeCode.Stream.final_text()

      assert result == "You asked: Hello Claude!"

      ClaudeCode.stop(session)
    end

    test "session handles tool use scenario" do
      ClaudeCode.Test.stub(ToolTestStub, fn _query, _opts ->
        [
          ClaudeCode.Test.text("I'll read that file"),
          ClaudeCode.Test.tool_use(name: "Read", input: %{path: "/tmp/test.txt"}),
          ClaudeCode.Test.tool_result(content: "Hello from file!"),
          ClaudeCode.Test.text("The file contains: Hello from file!"),
          ClaudeCode.Test.result(result: "The file contains: Hello from file!")
        ]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, ToolTestStub})

      messages =
        session
        |> ClaudeCode.stream("Read /tmp/test.txt")
        |> Enum.to_list()

      # Should have: system, text, tool_use, tool_result, text, result
      tool_uses =
        Enum.filter(messages, fn msg ->
          case msg do
            %AssistantMessage{message: %{content: content}} ->
              Enum.any?(content, &match?(%Content.ToolUseBlock{}, &1))

            _ ->
              false
          end
        end)

      assert length(tool_uses) == 1

      ClaudeCode.stop(session)
    end

    test "session handles error scenario" do
      ClaudeCode.Test.stub(ErrorTestStub, fn _query, _opts ->
        [ClaudeCode.Test.result(is_error: true, result: "Rate limit exceeded")]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, ErrorTestStub})

      messages =
        session
        |> ClaudeCode.stream("Hello")
        |> Enum.to_list()

      result = List.last(messages)
      assert %ResultMessage{is_error: true, result: "Rate limit exceeded"} = result

      ClaudeCode.stop(session)
    end
  end

  # ============================================================================
  # Stream Utilities Compatibility Tests
  # ============================================================================

  describe "compatibility with ClaudeCode.Stream utilities" do
    test "text_content/1 extracts text from mock messages" do
      ClaudeCode.Test.stub(TextContentStub, fn _q, _o ->
        [
          ClaudeCode.Test.text("First message"),
          ClaudeCode.Test.text("Second message")
        ]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, TextContentStub})

      texts =
        session
        |> ClaudeCode.stream("query")
        |> ClaudeCode.Stream.text_content()
        |> Enum.to_list()

      assert texts == ["First message", "Second message"]

      ClaudeCode.stop(session)
    end

    test "tool_uses/1 extracts tool uses from mock messages" do
      ClaudeCode.Test.stub(ToolUsesStub, fn _q, _o ->
        [
          ClaudeCode.Test.tool_use(name: "Read", input: %{path: "/a"}),
          ClaudeCode.Test.tool_result(content: "contents"),
          ClaudeCode.Test.tool_use(name: "Edit", input: %{path: "/b"})
        ]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, ToolUsesStub})

      tool_names =
        session
        |> ClaudeCode.stream("query")
        |> ClaudeCode.Stream.tool_uses()
        |> Enum.map(& &1.name)

      assert tool_names == ["Read", "Edit"]

      ClaudeCode.stop(session)
    end

    test "collect/1 works with mock messages" do
      ClaudeCode.Test.stub(CollectStub, fn _q, _o ->
        [
          ClaudeCode.Test.text("Hello"),
          ClaudeCode.Test.tool_use(name: "Read", input: %{path: "/x"}),
          ClaudeCode.Test.tool_result(content: "data"),
          ClaudeCode.Test.text("Done")
        ]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, CollectStub})

      collected =
        session
        |> ClaudeCode.stream("query")
        |> ClaudeCode.Stream.collect()

      assert collected.text == "HelloDone"
      assert length(collected.tool_calls) == 1
      assert collected.is_error == false

      ClaudeCode.stop(session)
    end
  end
end
