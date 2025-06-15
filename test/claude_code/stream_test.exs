defmodule ClaudeCode.StreamTest do
  use ExUnit.Case, async: true

  import ClaudeCode.Test.MessageFixtures

  alias ClaudeCode.Message
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
      assert match?(%Message.Assistant{}, hd(assistant_only))

      result_only = messages |> Stream.filter_type(:result) |> Enum.to_list()
      assert length(result_only) == 1
      assert match?(%Message.Result{}, hd(result_only))
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
      assert match?(%Message.System{}, Enum.at(truncated, 0))
      assert match?(%Message.Assistant{}, Enum.at(truncated, 1))
      assert match?(%Message.Result{}, Enum.at(truncated, 2))
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
end
