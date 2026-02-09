defmodule ClaudeCode.MessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.UserMessage

  describe "parse/1" do
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

      assert {:ok, %SystemMessage{}} = Message.parse(data)
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

      assert {:ok, %CompactBoundaryMessage{subtype: :compact_boundary}} = Message.parse(data)
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

      assert {:ok, %AssistantMessage{uuid: "msg-uuid-123"}} = Message.parse(data)
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

      assert {:ok, %AssistantMessage{uuid: nil}} = Message.parse(data)
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
               Message.parse(data)
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

      assert {:ok, %UserMessage{tool_use_result: tool_use_result}} = Message.parse(data)
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

      assert {:ok, %UserMessage{tool_use_result: nil}} = Message.parse(data)
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

      assert {:ok, %AssistantMessage{error: :rate_limit}} = Message.parse(data)
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

      assert {:ok, %AssistantMessage{error: nil}} = Message.parse(data)
    end

    test "parses result messages with new fields" do
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
              }} = Message.parse(data)

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
               Message.parse(data)
    end

    test "returns error for unknown message type" do
      data = %{"type" => "unknown"}
      assert {:error, {:unknown_message_type, "unknown"}} = Message.parse(data)
    end

    test "returns error for missing type" do
      data = %{"subtype" => "init"}
      assert {:error, :missing_type} = Message.parse(data)
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
              }} = Message.parse(data)

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
              }} = Message.parse(data)

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

      assert {:ok, %SystemMessage{subtype: :some_future_subtype}} = Message.parse(data)
    end

    test "returns error for system message without subtype" do
      data = %{"type" => "system"}
      assert {:error, :invalid_system_subtype} = Message.parse(data)
    end
  end

  describe "parse_all/1" do
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
               Message.parse_all(data)
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
    test "parses newline-delimited JSON stream with compact boundary" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}
      {"type":"assistant","uuid":"msg-uuid","message":{"id":"msg_123","type":"message","role":"assistant","model":"claude","content":[{"type":"text","text":"Hello"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"service_tier":"standard"}},"parent_tool_use_id":null,"session_id":"123"}
      {"type":"system","subtype":"compact_boundary","uuid":"compact-uuid","session_id":"123","compact_metadata":{"trigger":"auto","pre_tokens":5000}}
      {"type":"result","subtype":"success","uuid":"result-uuid","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Hello","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Message.parse_stream(stream)
      assert length(messages) == 4
      assert [%SystemMessage{}, %AssistantMessage{}, %CompactBoundaryMessage{}, %ResultMessage{}] = messages
    end

    test "handles empty lines in stream" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}

      {"type":"result","subtype":"success","uuid":"result-uuid","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Done","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Message.parse_stream(stream)
      assert length(messages) == 2
    end

    test "returns error for invalid JSON in stream" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}
      {invalid json}
      """

      assert {:error, {:json_decode_error, 1, _}} = Message.parse_stream(stream)
    end
  end

  describe "type detection" do
    test "message?/1 returns true for any message type" do
      {:ok, system} =
        SystemMessage.new(%{
          "type" => "system",
          "subtype" => "init",
          "uuid" => "550e8400-e29b-41d4-a716-446655440000",
          "cwd" => "/",
          "session_id" => "1",
          "tools" => [],
          "mcp_servers" => [],
          "model" => "claude",
          "permissionMode" => "default",
          "apiKeySource" => "env",
          "slashCommands" => [],
          "outputStyle" => "default"
        })

      assert Message.message?(system)
    end

    test "message?/1 returns true for compact boundary messages" do
      {:ok, compact} =
        CompactBoundaryMessage.new(%{
          "type" => "system",
          "subtype" => "compact_boundary",
          "uuid" => "550e8400-e29b-41d4-a716-446655440000",
          "session_id" => "1",
          "compact_metadata" => %{"trigger" => "auto", "pre_tokens" => 5000}
        })

      assert Message.message?(compact)
    end

    test "message?/1 returns true for non-init system messages" do
      {:ok, event} =
        SystemMessage.new(%{
          "type" => "system",
          "subtype" => "hook_started",
          "uuid" => "event-uuid",
          "session_id" => "1",
          "hook_id" => "hook-1"
        })

      assert Message.message?(event)
    end

    test "message?/1 returns false for non-messages" do
      refute Message.message?(%{})
      refute Message.message?("string")
      refute Message.message?(nil)
    end
  end

  describe "message type helpers" do
    test "message_type/1 returns the type of system message" do
      {:ok, system} =
        SystemMessage.new(%{
          "type" => "system",
          "subtype" => "init",
          "uuid" => "550e8400-e29b-41d4-a716-446655440000",
          "cwd" => "/",
          "session_id" => "1",
          "tools" => [],
          "mcp_servers" => [],
          "model" => "claude",
          "permissionMode" => "default",
          "apiKeySource" => "env",
          "slashCommands" => [],
          "outputStyle" => "default"
        })

      assert Message.message_type(system) == :system
    end

    test "message_type/1 returns the type of compact boundary message" do
      {:ok, compact} =
        CompactBoundaryMessage.new(%{
          "type" => "system",
          "subtype" => "compact_boundary",
          "uuid" => "550e8400-e29b-41d4-a716-446655440000",
          "session_id" => "1",
          "compact_metadata" => %{"trigger" => "auto", "pre_tokens" => 5000}
        })

      assert Message.message_type(compact) == :system
    end
  end

  describe "from fixture" do
    test "parses all messages from a real CLI session" do
      fixture_path = "test/fixtures/cli_messages/simple_hello.jsonl"
      content = File.read!(fixture_path)

      assert {:ok, messages} = Message.parse_stream(content)
      assert length(messages) == 3

      assert [%SystemMessage{}, %AssistantMessage{}, %ResultMessage{}] = messages

      # Verify session IDs match
      [system, assistant, result] = messages
      assert system.session_id == assistant.session_id
      assert assistant.session_id == result.session_id
    end
  end
end
