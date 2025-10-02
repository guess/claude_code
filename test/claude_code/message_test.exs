defmodule ClaudeCode.MessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message
  alias ClaudeCode.Message.Assistant
  alias ClaudeCode.Message.Result
  alias ClaudeCode.Message.System
  alias ClaudeCode.Message.User

  describe "parse/1" do
    test "parses system messages" do
      data = %{
        "type" => "system",
        "subtype" => "init",
        "cwd" => "/test",
        "session_id" => "123",
        "tools" => [],
        "mcp_servers" => [],
        "model" => "claude",
        "permissionMode" => "default",
        "apiKeySource" => "env"
      }

      assert {:ok, %System{}} = Message.parse(data)
    end

    test "parses assistant messages" do
      data = %{
        "type" => "assistant",
        "message" => %{
          "id" => "msg_123",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude",
          "content" => [%{"type" => "text", "text" => "Hello"}],
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
        "session_id" => "123"
      }

      assert {:ok, %Assistant{}} = Message.parse(data)
    end

    test "parses user messages" do
      data = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "123",
              "content" => "OK"
            }
          ]
        },
        "parent_tool_use_id" => nil,
        "session_id" => "123"
      }

      assert {:ok, %User{}} = Message.parse(data)
    end

    test "parses result messages" do
      data = %{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "duration_ms" => 100,
        "duration_api_ms" => 90,
        "num_turns" => 1,
        "result" => "Done",
        "session_id" => "123",
        "total_cost_usd" => 0.001,
        "usage" => %{
          "input_tokens" => 10,
          "cache_creation_input_tokens" => 0,
          "cache_read_input_tokens" => 0,
          "output_tokens" => 5,
          "server_tool_use" => %{"web_search_requests" => 0}
        }
      }

      assert {:ok, %Result{}} = Message.parse(data)
    end

    test "returns error for unknown message type" do
      data = %{"type" => "unknown"}
      assert {:error, {:unknown_message_type, "unknown"}} = Message.parse(data)
    end

    test "returns error for missing type" do
      data = %{"subtype" => "init"}
      assert {:error, :missing_type} = Message.parse(data)
    end
  end

  describe "parse_all/1" do
    test "parses a list of messages" do
      data = [
        %{
          "type" => "system",
          "subtype" => "init",
          "cwd" => "/test",
          "session_id" => "123",
          "tools" => [],
          "mcp_servers" => [],
          "model" => "claude",
          "permissionMode" => "default",
          "apiKeySource" => "env"
        },
        %{
          "type" => "assistant",
          "message" => %{
            "id" => "msg_123",
            "type" => "message",
            "role" => "assistant",
            "model" => "claude",
            "content" => [%{"type" => "text", "text" => "Hi"}],
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
          "session_id" => "123"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "is_error" => false,
          "duration_ms" => 100,
          "duration_api_ms" => 90,
          "num_turns" => 1,
          "result" => "Hi",
          "session_id" => "123",
          "total_cost_usd" => 0.001,
          "usage" => %{
            "input_tokens" => 1,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0,
            "output_tokens" => 1,
            "server_tool_use" => %{"web_search_requests" => 0}
          }
        }
      ]

      assert {:ok, [%System{}, %Assistant{}, %Result{}]} = Message.parse_all(data)
    end

    test "returns error if any message fails to parse" do
      data = [
        # Missing required fields
        %{"type" => "system", "subtype" => "init"},
        %{"type" => "assistant"}
      ]

      assert {:error, {:parse_error, 0, _}} = Message.parse_all(data)
    end

    test "handles empty list" do
      assert {:ok, []} = Message.parse_all([])
    end
  end

  describe "parse_stream/1" do
    test "parses newline-delimited JSON stream" do
      stream = """
      {"type":"system","subtype":"init","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env"}
      {"type":"assistant","message":{"id":"msg_123","type":"message","role":"assistant","model":"claude","content":[{"type":"text","text":"Hello"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"service_tier":"standard"}},"parent_tool_use_id":null,"session_id":"123"}
      {"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Hello","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Message.parse_stream(stream)
      assert length(messages) == 3
      assert [%System{}, %Assistant{}, %Result{}] = messages
    end

    test "handles empty lines in stream" do
      stream = """
      {"type":"system","subtype":"init","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env"}

      {"type":"result","subtype":"success","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Done","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Message.parse_stream(stream)
      assert length(messages) == 2
    end

    test "returns error for invalid JSON in stream" do
      stream = """
      {"type":"system","subtype":"init","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env"}
      {invalid json}
      """

      assert {:error, {:json_decode_error, 1, _}} = Message.parse_stream(stream)
    end
  end

  describe "type detection" do
    test "message?/1 returns true for any message type" do
      {:ok, system} =
        System.new(%{
          "type" => "system",
          "subtype" => "init",
          "cwd" => "/",
          "session_id" => "1",
          "tools" => [],
          "mcp_servers" => [],
          "model" => "claude",
          "permissionMode" => "default",
          "apiKeySource" => "env"
        })

      assert Message.message?(system)
    end

    test "message?/1 returns false for non-messages" do
      refute Message.message?(%{})
      refute Message.message?("string")
      refute Message.message?(nil)
    end
  end

  describe "message type helpers" do
    test "message_type/1 returns the type of message" do
      {:ok, system} =
        System.new(%{
          "type" => "system",
          "subtype" => "init",
          "cwd" => "/",
          "session_id" => "1",
          "tools" => [],
          "mcp_servers" => [],
          "model" => "claude",
          "permissionMode" => "default",
          "apiKeySource" => "env"
        })

      assert Message.message_type(system) == :system
    end
  end

  describe "from fixture" do
    test "parses all messages from a real CLI session" do
      fixture_path = "test/fixtures/cli_messages/simple_hello.jsonl"
      content = File.read!(fixture_path)

      assert {:ok, messages} = Message.parse_stream(content)
      assert length(messages) == 3

      assert [%System{}, %Assistant{}, %Result{}] = messages

      # Verify session IDs match
      [system, assistant, result] = messages
      assert system.session_id == assistant.session_id
      assert assistant.session_id == result.session_id
    end
  end
end
