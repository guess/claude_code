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

    test "parses assistant messages with uuid" do
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

    test "parses assistant messages without uuid" do
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

      assert {:ok, %AssistantMessage{uuid: nil}} = Parser.parse_message(data)
    end

    test "parses user messages with uuid and parent_tool_use_id" do
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

      assert {:ok, %UserMessage{uuid: "user-uuid-456", parent_tool_use_id: "tool-parent-123"}} =
               Parser.parse_message(data)
    end

    test "parses user messages with tool_use_result metadata" do
      data = %{
        "type" => "user",
        "uuid" => "user-uuid-789",
        "message" => %{
          "role" => "user",
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "tool-123",
              "content" => "file contents here"
            }
          ]
        },
        "parent_tool_use_id" => nil,
        "session_id" => "123",
        "tool_use_result" => %{
          "type" => "text",
          "file" => %{
            "filePath" => "/path/to/file.ex",
            "content" => "defmodule Foo do\nend\n",
            "numLines" => 2,
            "startLine" => 1,
            "totalLines" => 2
          }
        }
      }

      assert {:ok, %UserMessage{tool_use_result: tool_use_result}} = Parser.parse_message(data)
      assert tool_use_result["type"] == "text"
      assert tool_use_result["file"]["filePath"] == "/path/to/file.ex"
    end

    test "parses user messages without tool_use_result" do
      data = %{
        "type" => "user",
        "uuid" => "user-uuid-790",
        "message" => %{
          "role" => "user",
          "content" => "Hello"
        },
        "session_id" => "123"
      }

      assert {:ok, %UserMessage{tool_use_result: nil}} = Parser.parse_message(data)
    end

    test "parses assistant messages with error field" do
      data = %{
        "type" => "assistant",
        "uuid" => "msg-uuid-err",
        "message" => %{
          "id" => "msg_err",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude",
          "content" => [],
          "stop_reason" => nil,
          "stop_sequence" => nil,
          "usage" => %{
            "input_tokens" => 0,
            "output_tokens" => 0
          }
        },
        "parent_tool_use_id" => nil,
        "session_id" => "123",
        "error" => "rate_limit"
      }

      assert {:ok, %AssistantMessage{error: :rate_limit}} = Parser.parse_message(data)
    end

    test "parses assistant messages without error field" do
      data = %{
        "type" => "assistant",
        "uuid" => "msg-uuid-ok",
        "message" => %{
          "id" => "msg_ok",
          "type" => "message",
          "role" => "assistant",
          "model" => "claude",
          "content" => [%{"type" => "text", "text" => "Hello"}],
          "stop_reason" => nil,
          "stop_sequence" => nil,
          "usage" => %{
            "input_tokens" => 1,
            "output_tokens" => 1
          }
        },
        "parent_tool_use_id" => nil,
        "session_id" => "123"
      }

      assert {:ok, %AssistantMessage{error: nil}} = Parser.parse_message(data)
    end

    test "parses result messages with all fields" do
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
        },
        "modelUsage" => %{
          "claude-3-sonnet" => %{
            "input_tokens" => 10,
            "output_tokens" => 5,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0
          }
        },
        "permission_denials" => [
          %{
            "tool_name" => "web_search",
            "tool_use_id" => "tool_123",
            "tool_input" => %{"query" => "test"}
          }
        ],
        "structured_output" => %{"key" => "value"}
      }

      assert {:ok,
              %ResultMessage{
                uuid: "result-uuid-789",
                model_usage: model_usage,
                permission_denials: denials,
                structured_output: output
              }} = Parser.parse_message(data)

      assert model_usage != nil
      assert denials != nil
      assert output == %{"key" => "value"}
    end

    test "parses result error messages with errors field" do
      data = %{
        "type" => "result",
        "subtype" => "error_max_turns",
        "uuid" => "result-error-uuid",
        "is_error" => true,
        "duration_ms" => 100,
        "duration_api_ms" => 90,
        "num_turns" => 10,
        "result" => "Max turns exceeded",
        "session_id" => "123",
        "total_cost_usd" => 0.05,
        "usage" => %{
          "input_tokens" => 100,
          "cache_creation_input_tokens" => 0,
          "cache_read_input_tokens" => 0,
          "output_tokens" => 50,
          "server_tool_use" => %{"web_search_requests" => 0}
        },
        "errors" => ["Error 1", "Error 2"]
      }

      assert {:ok, %ResultMessage{subtype: :error_max_turns, errors: ["Error 1", "Error 2"]}} =
               Parser.parse_message(data)
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

    test "parses hook_started system messages" do
      data = %{
        "type" => "system",
        "subtype" => "hook_started",
        "hook_id" => "abc-123",
        "hook_name" => "SessionStart:startup",
        "hook_event" => "SessionStart",
        "uuid" => "event-uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok,
              %SystemMessage{
                type: :system,
                subtype: :hook_started,
                session_id: "session-1",
                uuid: "event-uuid-1",
                data: data_map
              }} = Parser.parse_message(data)

      assert data_map.hook_id == "abc-123"
      assert data_map.hook_name == "SessionStart:startup"
      assert data_map.hook_event == "SessionStart"
    end

    test "parses hook_response system messages" do
      data = %{
        "type" => "system",
        "subtype" => "hook_response",
        "hook_id" => "abc-123",
        "hook_name" => "SessionStart:startup",
        "hook_event" => "SessionStart",
        "output" => "hook output",
        "stdout" => "hook stdout",
        "stderr" => "",
        "exit_code" => 0,
        "outcome" => "success",
        "uuid" => "event-uuid-2",
        "session_id" => "session-1"
      }

      assert {:ok,
              %SystemMessage{
                subtype: :hook_response,
                data: data_map
              }} = Parser.parse_message(data)

      assert data_map.hook_id == "abc-123"
      assert data_map.exit_code == 0
      assert data_map.outcome == "success"
    end

    test "parses unknown system subtypes as SystemMessage" do
      data = %{
        "type" => "system",
        "subtype" => "some_future_subtype",
        "uuid" => "event-uuid",
        "session_id" => "session-1",
        "custom_field" => "custom_value"
      }

      assert {:ok, %SystemMessage{subtype: :some_future_subtype}} = Parser.parse_message(data)
    end

    test "handles rate_limit_event as informational message" do
      msg = %{
        "type" => "rate_limit_event",
        "rate_limit_info" => %{
          "status" => "allowed",
          "rateLimitType" => "five_hour",
          "resetsAt" => 1_772_110_800
        }
      }

      assert {:ok, :rate_limit_event} = Parser.parse_message(msg)
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
    test "parses a list of messages including compact boundary" do
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
          "type" => "assistant",
          "uuid" => "msg-uuid",
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
          "type" => "system",
          "subtype" => "compact_boundary",
          "uuid" => "compact-uuid",
          "session_id" => "123",
          "compact_metadata" => %{"trigger" => "auto", "pre_tokens" => 5000}
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

      assert {:ok, [%SystemMessage{}, %AssistantMessage{}, %CompactBoundaryMessage{}, %ResultMessage{}]} =
               Parser.parse_all_messages(data)
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
    test "parses newline-delimited JSON stream with compact boundary" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}
      {"type":"assistant","uuid":"msg-uuid","message":{"id":"msg_123","type":"message","role":"assistant","model":"claude","content":[{"type":"text","text":"Hello"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"service_tier":"standard"}},"parent_tool_use_id":null,"session_id":"123"}
      {"type":"system","subtype":"compact_boundary","uuid":"compact-uuid","session_id":"123","compact_metadata":{"trigger":"auto","pre_tokens":5000}}
      {"type":"result","subtype":"success","uuid":"result-uuid","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Hello","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Parser.parse_stream(stream)
      assert length(messages) == 4
      assert [%SystemMessage{}, %AssistantMessage{}, %CompactBoundaryMessage{}, %ResultMessage{}] = messages
    end

    test "handles empty lines in stream" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}

      {"type":"result","subtype":"success","uuid":"result-uuid","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Done","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Parser.parse_stream(stream)
      assert length(messages) == 2
    end

    test "returns error for invalid JSON in stream" do
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
  # from fixture
  # ============================================================================

  describe "from fixture" do
    test "parses all messages from a real CLI session" do
      fixture_path = "test/fixtures/cli_messages/simple_hello.jsonl"
      content = File.read!(fixture_path)

      assert {:ok, messages} = Parser.parse_stream(content)
      assert length(messages) == 3

      assert [%SystemMessage{}, %AssistantMessage{}, %ResultMessage{}] = messages

      # Verify session IDs match
      [system, assistant, result] = messages
      assert system.session_id == assistant.session_id
      assert assistant.session_id == result.session_id
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

      assert {:ok, %ThinkingBlock{thinking: "Let me reason through this...", signature: "sig_abc123"}} =
               Parser.parse_content(data)
    end

    test "returns error for thinking block missing signature" do
      data = %{"type" => "thinking", "thinking" => "Some reasoning"}

      assert {:error, {:missing_fields, [:signature]}} = Parser.parse_content(data)
    end

    test "returns error for thinking block missing thinking field" do
      data = %{"type" => "thinking", "signature" => "sig_123"}

      assert {:error, {:missing_fields, [:thinking]}} = Parser.parse_content(data)
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
