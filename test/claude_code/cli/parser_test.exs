defmodule ClaudeCode.CLI.ParserTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.UserMessage

  # ============================================================================
  # parse_message/1
  # ============================================================================

  describe "parse_message/1" do
    test "parses system init messages" do
      data = %{
        "type" => "system",
        "subtype" => "init",
        "uuid" => "550e8400-e29b-41d4-a716-446655440000",
        "cwd" => "/test",
        "session_id" => "123",
        "tools" => [],
        "mcp_servers" => [],
        "model" => "claude",
        "permissionMode" => "default",
        "apiKeySource" => "env",
        "slashCommands" => [],
        "outputStyle" => "default"
      }

      assert {:ok, %SystemMessage{type: :system, subtype: :init}} = Parser.parse_message(data)
    end

    test "parses system compact_boundary messages" do
      data = %{
        "type" => "system",
        "subtype" => "compact_boundary",
        "uuid" => "550e8400-e29b-41d4-a716-446655440000",
        "session_id" => "123",
        "compact_metadata" => %{
          "trigger" => "auto",
          "pre_tokens" => 5000
        }
      }

      assert {:ok, %CompactBoundaryMessage{subtype: :compact_boundary}} = Parser.parse_message(data)
    end

    test "parses assistant messages" do
      data = %{
        "type" => "assistant",
        "uuid" => "msg-uuid-123",
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

      assert {:ok, %AssistantMessage{uuid: "msg-uuid-123"}} = Parser.parse_message(data)
    end

    test "parses user messages" do
      data = %{
        "type" => "user",
        "uuid" => "user-uuid-456",
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
        "parent_tool_use_id" => "tool-parent-123",
        "session_id" => "123"
      }

      assert {:ok, %UserMessage{uuid: "user-uuid-456"}} = Parser.parse_message(data)
    end

    test "parses result messages" do
      data = %{
        "type" => "result",
        "subtype" => "success",
        "uuid" => "result-uuid-789",
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

      assert {:ok, %ResultMessage{uuid: "result-uuid-789"}} = Parser.parse_message(data)
    end

    test "parses stream_event messages" do
      data = %{
        "type" => "stream_event",
        "event" => %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "text_delta", "text" => "Hi"}
        },
        "session_id" => "123"
      }

      assert {:ok, %PartialAssistantMessage{}} = Parser.parse_message(data)
    end

    test "returns error for unknown message type" do
      assert {:error, {:unknown_message_type, "unknown"}} = Parser.parse_message(%{"type" => "unknown"})
    end

    test "returns error for missing type" do
      assert {:error, :missing_type} = Parser.parse_message(%{"subtype" => "init"})
    end

    test "returns error for system message without subtype" do
      assert {:error, :invalid_system_subtype} = Parser.parse_message(%{"type" => "system"})
    end
  end

  # ============================================================================
  # parse_all_messages/1
  # ============================================================================

  describe "parse_all_messages/1" do
    test "parses a list of messages" do
      data = [
        %{
          "type" => "system",
          "subtype" => "init",
          "uuid" => "550e8400-e29b-41d4-a716-446655440000",
          "cwd" => "/test",
          "session_id" => "123",
          "tools" => [],
          "mcp_servers" => [],
          "model" => "claude",
          "permissionMode" => "default",
          "apiKeySource" => "env",
          "slashCommands" => [],
          "outputStyle" => "default"
        },
        %{
          "type" => "result",
          "subtype" => "success",
          "uuid" => "result-uuid",
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

      assert {:ok, [%SystemMessage{}, %ResultMessage{}]} = Parser.parse_all_messages(data)
    end

    test "returns error with index on first failure" do
      data = [
        %{"type" => "system", "subtype" => "init"},
        %{"type" => "unknown"}
      ]

      assert {:error, {:parse_error, 0, _}} = Parser.parse_all_messages(data)
    end

    test "handles empty list" do
      assert {:ok, []} = Parser.parse_all_messages([])
    end
  end

  # ============================================================================
  # parse_stream/1
  # ============================================================================

  describe "parse_stream/1" do
    test "parses newline-delimited JSON stream" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}
      {"type":"result","subtype":"success","uuid":"result-uuid","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Done","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, [%SystemMessage{}, %ResultMessage{}]} = Parser.parse_stream(stream)
    end

    test "handles empty lines in stream" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}

      {"type":"result","subtype":"success","uuid":"result-uuid","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Done","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Parser.parse_stream(stream)
      assert length(messages) == 2
    end

    test "returns error for invalid JSON" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}
      {invalid json}
      """

      assert {:error, {:json_decode_error, 1, _}} = Parser.parse_stream(stream)
    end

    test "returns error for invalid message in stream" do
      stream = """
      {"type":"unknown"}
      """

      assert {:error, {:parse_error, 0, {:unknown_message_type, "unknown"}}} = Parser.parse_stream(stream)
    end
  end

  # ============================================================================
  # parse_content/1
  # ============================================================================

  describe "parse_content/1" do
    test "parses text content blocks" do
      data = %{"type" => "text", "text" => "Hello!"}

      assert {:ok, %TextBlock{text: "Hello!"}} = Parser.parse_content(data)
    end

    test "parses thinking content blocks" do
      data = %{
        "type" => "thinking",
        "thinking" => "Let me reason through this...",
        "signature" => "sig_abc123"
      }

      assert {:ok, %ThinkingBlock{thinking: "Let me reason through this..."}} = Parser.parse_content(data)
    end

    test "parses tool_use content blocks" do
      data = %{
        "type" => "tool_use",
        "id" => "toolu_123",
        "name" => "Read",
        "input" => %{"file" => "test.txt"}
      }

      assert {:ok, %ToolUseBlock{id: "toolu_123", name: "Read"}} = Parser.parse_content(data)
    end

    test "parses tool_result content blocks" do
      data = %{
        "type" => "tool_result",
        "tool_use_id" => "toolu_123",
        "content" => "Success"
      }

      assert {:ok, %ToolResultBlock{tool_use_id: "toolu_123"}} = Parser.parse_content(data)
    end

    test "returns error for unknown content type" do
      assert {:error, {:unknown_content_type, "unknown"}} = Parser.parse_content(%{"type" => "unknown"})
    end

    test "returns error for missing type" do
      assert {:error, :missing_type} = Parser.parse_content(%{"text" => "Hello"})
    end
  end

  # ============================================================================
  # parse_all_contents/1
  # ============================================================================

  describe "parse_all_contents/1" do
    test "parses a list of content blocks" do
      data = [
        %{"type" => "text", "text" => "I'll help you."},
        %{"type" => "tool_use", "id" => "123", "name" => "Read", "input" => %{}},
        %{"type" => "text", "text" => "Done!"}
      ]

      assert {:ok, [%TextBlock{}, %ToolUseBlock{}, %TextBlock{}]} = Parser.parse_all_contents(data)
    end

    test "returns error with index on first failure" do
      data = [
        %{"type" => "text", "text" => "OK"},
        %{"type" => "invalid"},
        %{"type" => "text", "text" => "More"}
      ]

      assert {:error, {:parse_error, 1, {:unknown_content_type, "invalid"}}} = Parser.parse_all_contents(data)
    end

    test "handles empty list" do
      assert {:ok, []} = Parser.parse_all_contents([])
    end
  end
end
