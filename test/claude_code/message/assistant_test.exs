defmodule ClaudeCode.Message.AssistantTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.Assistant
  alias ClaudeCode.Content.{Text, ToolUse}

  describe "new/1" do
    test "parses a valid assistant message with text content" do
      json = %{
        "type" => "assistant",
        "message" => %{
          "id" => "msg_123",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude-opus-4",
          "content" => [
            %{"type" => "text", "text" => "Hello, I can help you!"}
          ],
          "stop_reason" => nil,
          "stop_sequence" => nil,
          "usage" => %{
            "input_tokens" => 100,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 50,
            "output_tokens" => 25,
            "service_tier" => "standard"
          }
        },
        "parent_tool_use_id" => nil,
        "session_id" => "session-123"
      }

      assert {:ok, message} = Assistant.new(json)
      assert message.type == :assistant
      assert message.message_id == "msg_123"
      assert message.role == :assistant
      assert message.model == "claude-opus-4"
      assert message.session_id == "session-123"
      assert message.parent_tool_use_id == nil
      assert message.stop_reason == nil
      assert message.stop_sequence == nil
      
      assert [%Text{text: "Hello, I can help you!"}] = message.content
      
      assert message.usage.input_tokens == 100
      assert message.usage.output_tokens == 25
    end

    test "parses assistant message with tool use content" do
      json = %{
        "type" => "assistant",
        "message" => %{
          "id" => "msg_456",
          "type" => "message", 
          "role" => "assistant",
          "model" => "claude-opus-4",
          "content" => [
            %{"type" => "text", "text" => "I'll read that file for you."},
            %{
              "type" => "tool_use",
              "id" => "toolu_789",
              "name" => "Read",
              "input" => %{"file_path" => "/test.txt"}
            }
          ],
          "stop_reason" => "tool_use",
          "stop_sequence" => nil,
          "usage" => %{
            "input_tokens" => 200,
            "cache_creation_input_tokens" => 10,
            "cache_read_input_tokens" => 100,
            "output_tokens" => 50,
            "service_tier" => "standard"
          }
        },
        "parent_tool_use_id" => nil,
        "session_id" => "session-456"
      }

      assert {:ok, message} = Assistant.new(json)
      assert message.stop_reason == :tool_use
      assert length(message.content) == 2
      
      assert [%Text{text: "I'll read that file for you."}, 
              %ToolUse{name: "Read", id: "toolu_789"}] = message.content
    end

    test "handles empty content array" do
      json = %{
        "type" => "assistant",
        "message" => %{
          "id" => "msg_empty",
          "type" => "message",
          "role" => "assistant", 
          "model" => "claude",
          "content" => [],
          "stop_reason" => nil,
          "stop_sequence" => nil,
          "usage" => %{
            "input_tokens" => 0,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0,
            "output_tokens" => 0,
            "service_tier" => "standard"
          }
        },
        "parent_tool_use_id" => nil,
        "session_id" => "empty-session"
      }

      assert {:ok, message} = Assistant.new(json)
      assert message.content == []
    end

    test "parses stop_reason as atom" do
      base_json = fn stop_reason ->
        %{
          "type" => "assistant",
          "message" => %{
            "id" => "msg_stop",
            "type" => "message",
            "role" => "assistant",
            "model" => "claude",
            "content" => [%{"type" => "text", "text" => "Done"}],
            "stop_reason" => stop_reason,
            "stop_sequence" => nil,
            "usage" => %{
              "input_tokens" => 0,
              "cache_creation_input_tokens" => 0,
              "cache_read_input_tokens" => 0,
              "output_tokens" => 0,
              "service_tier" => "standard"
            }
          },
          "parent_tool_use_id" => nil,
          "session_id" => "test"
        }
      end

      {:ok, msg1} = Assistant.new(base_json.("tool_use"))
      assert msg1.stop_reason == :tool_use

      {:ok, msg2} = Assistant.new(base_json.("end_turn"))
      assert msg2.stop_reason == :end_turn

      {:ok, msg3} = Assistant.new(base_json.(nil))
      assert msg3.stop_reason == nil
    end

    test "returns error for invalid type" do
      json = %{"type" => "user"}
      assert {:error, :invalid_message_type} = Assistant.new(json)
    end

    test "returns error for missing message wrapper" do
      json = %{"type" => "assistant"}
      assert {:error, :missing_message} = Assistant.new(json)
    end

    test "returns error if content parsing fails" do
      json = %{
        "type" => "assistant",
        "message" => %{
          "id" => "msg_bad",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude",
          "content" => [
            %{"type" => "invalid_type"}
          ],
          "stop_reason" => nil,
          "stop_sequence" => nil,
          "usage" => %{
            "input_tokens" => 0,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0,
            "output_tokens" => 0,
            "service_tier" => "standard"
          }
        },
        "parent_tool_use_id" => nil,
        "session_id" => "bad"
      }

      assert {:error, {:content_parse_error, _}} = Assistant.new(json)
    end
  end

  describe "type guards" do
    test "is_assistant_message?/1 returns true for assistant messages" do
      {:ok, message} = Assistant.new(valid_assistant_json())
      assert Assistant.is_assistant_message?(message)
    end

    test "is_assistant_message?/1 returns false for non-assistant messages" do
      refute Assistant.is_assistant_message?(%{type: :user})
      refute Assistant.is_assistant_message?(nil)
      refute Assistant.is_assistant_message?("not a message")
    end
  end

  describe "from fixture" do
    test "parses real CLI assistant message with text" do
      fixture_path = "test/fixtures/cli_messages/simple_hello.json"
      lines = File.read!(fixture_path) |> String.split("\n", trim: true)
      
      # Second line should be assistant message
      {:ok, json} = Jason.decode(Enum.at(lines, 1))
      
      assert json["type"] == "assistant"
      assert {:ok, message} = Assistant.new(json)
      assert message.type == :assistant
      assert is_binary(message.message_id)
      assert [%Text{text: text}] = message.content
      assert text =~ "Hello"
    end

    test "parses real CLI assistant message with tool use" do
      fixture_path = "test/fixtures/cli_messages/file_listing.json"
      lines = File.read!(fixture_path) |> String.split("\n", trim: true)
      
      # Find assistant message with tool use
      assistant_messages = Enum.filter(lines, fn line ->
        case Jason.decode(line) do
          {:ok, %{"type" => "assistant"}} -> true
          _ -> false
        end
      end)
      
      # Should have at least one assistant message with tool use
      assert Enum.any?(assistant_messages, fn line ->
        {:ok, json} = Jason.decode(line)
        {:ok, message} = Assistant.new(json)
        
        Enum.any?(message.content, fn content ->
          match?(%ToolUse{}, content)
        end)
      end)
    end
  end

  defp valid_assistant_json do
    %{
      "type" => "assistant",
      "message" => %{
        "id" => "msg_test",
        "type" => "message",
        "role" => "assistant",
        "model" => "claude",
        "content" => [%{"type" => "text", "text" => "Test"}],
        "stop_reason" => nil,
        "stop_sequence" => nil,
        "usage" => %{
          "input_tokens" => 1,
          "cache_creation_input_tokens" => 0,
          "cache_read_input_tokens" => 0,
          "output_tokens" => 1,
          "service_tier" => "standard"
        }
      },
      "parent_tool_use_id" => nil,
      "session_id" => "test-session"
    }
  end
end