defmodule ClaudeCode.Message.AssistantMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.Message.AssistantMessage

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

      assert {:ok, message} = AssistantMessage.new(json)
      assert message.type == :assistant
      assert message.message.id == "msg_123"
      assert message.message.role == :assistant
      assert message.message.model == "claude-opus-4"
      assert message.session_id == "session-123"
      assert message.message.stop_reason == nil
      assert message.message.stop_sequence == nil

      assert [%TextBlock{text: "Hello, I can help you!"}] = message.message.content

      assert message.message.usage.input_tokens == 100
      assert message.message.usage.output_tokens == 25
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

      assert {:ok, message} = AssistantMessage.new(json)
      assert message.message.stop_reason == :tool_use
      assert length(message.message.content) == 2

      assert [%TextBlock{text: "I'll read that file for you."}, %ToolUseBlock{name: "Read", id: "toolu_789"}] =
               message.message.content
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

      assert {:ok, message} = AssistantMessage.new(json)
      assert message.message.content == []
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

      {:ok, msg1} = AssistantMessage.new(base_json.("tool_use"))
      assert msg1.message.stop_reason == :tool_use

      {:ok, msg2} = AssistantMessage.new(base_json.("end_turn"))
      assert msg2.message.stop_reason == :end_turn

      {:ok, msg3} = AssistantMessage.new(base_json.(nil))
      assert msg3.message.stop_reason == nil
    end

    test "returns error for invalid type" do
      json = %{"type" => "user"}
      assert {:error, :invalid_message_type} = AssistantMessage.new(json)
    end

    test "returns error for missing message wrapper" do
      json = %{"type" => "assistant"}
      assert {:error, :missing_message} = AssistantMessage.new(json)
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

      assert {:error, {:content_parse_error, _}} = AssistantMessage.new(json)
    end
  end

  describe "type guards" do
    test "assistant_message?/1 returns true for assistant messages" do
      {:ok, message} = AssistantMessage.new(valid_assistant_json())
      assert AssistantMessage.assistant_message?(message)
    end

    test "assistant_message?/1 returns false for non-assistant messages" do
      refute AssistantMessage.assistant_message?(%{type: :user})
      refute AssistantMessage.assistant_message?(nil)
      refute AssistantMessage.assistant_message?("not a message")
    end
  end

  describe "from fixture" do
    test "parses real CLI assistant message with text" do
      fixture_path = "test/fixtures/cli_messages/simple_hello.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Second line should be assistant message
      {:ok, json} = Jason.decode(Enum.at(lines, 1))

      assert json["type"] == "assistant"
      assert {:ok, message} = AssistantMessage.new(json)
      assert message.type == :assistant
      assert is_binary(message.message.id)
      assert [%TextBlock{text: text}] = message.message.content
      assert text =~ "Hello"
    end

    test "parses real CLI assistant message with tool use" do
      fixture_path = "test/fixtures/cli_messages/file_listing.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find assistant message with tool use
      assistant_messages =
        Enum.filter(lines, fn line ->
          case Jason.decode(line) do
            {:ok, %{"type" => "assistant"}} -> true
            _ -> false
          end
        end)

      # Should have at least one assistant message with tool use
      assert Enum.any?(assistant_messages, fn line ->
               {:ok, json} = Jason.decode(line)
               {:ok, message} = AssistantMessage.new(json)

               Enum.any?(message.message.content, fn content ->
                 match?(%ToolUseBlock{}, content)
               end)
             end)
    end
  end

  describe "error field" do
    test "parses max_output_tokens error" do
      json = Map.put(valid_assistant_json(), "error", "max_output_tokens")

      assert {:ok, message} = AssistantMessage.new(json)
      assert message.error == :max_output_tokens
    end

    test "parses known error types" do
      for {error_str, error_atom} <- [
            {"authentication_failed", :authentication_failed},
            {"billing_error", :billing_error},
            {"rate_limit", :rate_limit},
            {"invalid_request", :invalid_request},
            {"server_error", :server_error},
            {"unknown", :unknown},
            {"max_output_tokens", :max_output_tokens}
          ] do
        json = Map.put(valid_assistant_json(), "error", error_str)
        assert {:ok, message} = AssistantMessage.new(json)
        assert message.error == error_atom
      end
    end

    test "error defaults to nil" do
      assert {:ok, message} = AssistantMessage.new(valid_assistant_json())
      assert message.error == nil
    end
  end

  describe "usage fields" do
    test "parses inference_geo from usage" do
      json = valid_assistant_json()
      json = put_in(json, ["message", "usage", "inference_geo"], "not_available")

      assert {:ok, message} = AssistantMessage.new(json)
      assert message.message.usage.inference_geo == "not_available"
    end

    test "handles missing inference_geo" do
      assert {:ok, message} = AssistantMessage.new(valid_assistant_json())
      assert message.message.usage.inference_geo == nil
    end

    test "parses cache_creation from usage" do
      json = valid_assistant_json()

      json =
        put_in(json, ["message", "usage", "cache_creation"], %{
          "ephemeral_5m_input_tokens" => 100,
          "ephemeral_1h_input_tokens" => 200
        })

      assert {:ok, message} = AssistantMessage.new(json)
      assert message.message.usage.cache_creation.ephemeral_5m_input_tokens == 100
      assert message.message.usage.cache_creation.ephemeral_1h_input_tokens == 200
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
