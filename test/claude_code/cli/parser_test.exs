defmodule ClaudeCode.CLI.ParserTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Content.CompactionBlock
  alias ClaudeCode.Content.ContainerUploadBlock
  alias ClaudeCode.Content.MCPToolResultBlock
  alias ClaudeCode.Content.MCPToolUseBlock
  alias ClaudeCode.Content.RedactedThinkingBlock
  alias ClaudeCode.Content.ServerToolResultBlock
  alias ClaudeCode.Content.ServerToolUseBlock
  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.AuthStatusMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage.CompactBoundary
  alias ClaudeCode.Message.SystemMessage.ElicitationComplete
  alias ClaudeCode.Message.SystemMessage.FilesPersisted
  alias ClaudeCode.Message.SystemMessage.HookProgress
  alias ClaudeCode.Message.SystemMessage.HookResponse
  alias ClaudeCode.Message.SystemMessage.HookStarted
  alias ClaudeCode.Message.SystemMessage.Init
  alias ClaudeCode.Message.SystemMessage.LocalCommandOutput
  alias ClaudeCode.Message.SystemMessage.Status
  alias ClaudeCode.Message.SystemMessage.TaskNotification
  alias ClaudeCode.Message.SystemMessage.TaskProgress
  alias ClaudeCode.Message.SystemMessage.TaskStarted
  alias ClaudeCode.Message.ToolProgressMessage
  alias ClaudeCode.Message.ToolUseSummaryMessage
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
        "permission_mode" => "default",
        "api_key_source" => "env",
        "slash_commands" => [],
        "output_style" => "default"
      }

      assert {:ok, %Init{type: :system, subtype: :init}} = Parser.parse_message(data)
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

      assert {:ok, %CompactBoundary{subtype: :compact_boundary}} = Parser.parse_message(data)
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
            "file_path" => "/path/to/file.ex",
            "content" => "defmodule Foo do\nend\n",
            "num_lines" => 2,
            "start_line" => 1,
            "total_lines" => 2
          }
        }
      }

      assert {:ok, %UserMessage{tool_use_result: tool_use_result}} = Parser.parse_message(data)
      assert tool_use_result["type"] == "text"
      assert tool_use_result["file"]["file_path"] == "/path/to/file.ex"
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
        "model_usage" => %{
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
              %HookStarted{
                type: :system,
                subtype: :hook_started,
                session_id: "session-1",
                uuid: "event-uuid-1",
                hook_id: "abc-123",
                hook_name: "SessionStart:startup",
                hook_event: "SessionStart"
              }} = Parser.parse_message(data)
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
              %HookResponse{
                subtype: :hook_response,
                hook_id: "abc-123",
                exit_code: 0,
                outcome: :success
              }} = Parser.parse_message(data)
    end

    test "returns error for unknown system subtypes" do
      data = %{
        "type" => "system",
        "subtype" => "some_future_subtype",
        "uuid" => "event-uuid",
        "session_id" => "session-1",
        "custom_field" => "custom_value"
      }

      assert {:error, {:unknown_system_subtype, "some_future_subtype"}} = Parser.parse_message(data)
    end

    test "parses rate_limit_event messages" do
      data = %{
        "type" => "rate_limit_event",
        "rate_limit_info" => %{
          "status" => "allowed_warning",
          "resets_at" => 1_700_000_000_000,
          "utilization" => 0.85
        },
        "uuid" => "uuid-rl",
        "session_id" => "session-1"
      }

      assert {:ok, %RateLimitEvent{type: :rate_limit_event}} = Parser.parse_message(data)
    end

    test "parses tool_progress messages" do
      data = %{
        "type" => "tool_progress",
        "tool_use_id" => "toolu_abc",
        "tool_name" => "Bash",
        "parent_tool_use_id" => nil,
        "elapsed_time_seconds" => 3.5,
        "uuid" => "uuid-tp",
        "session_id" => "session-1"
      }

      assert {:ok, %ToolProgressMessage{type: :tool_progress, tool_name: "Bash"}} = Parser.parse_message(data)
    end

    test "parses tool_use_summary messages" do
      data = %{
        "type" => "tool_use_summary",
        "summary" => "Read 3 files",
        "preceding_tool_use_ids" => ["toolu_1", "toolu_2"],
        "uuid" => "uuid-tus",
        "session_id" => "session-1"
      }

      assert {:ok, %ToolUseSummaryMessage{type: :tool_use_summary, summary: "Read 3 files"}} =
               Parser.parse_message(data)
    end

    test "parses auth_status messages" do
      data = %{
        "type" => "auth_status",
        "is_authenticating" => true,
        "output" => ["Authenticating..."],
        "uuid" => "uuid-auth",
        "session_id" => "session-1"
      }

      assert {:ok, %AuthStatusMessage{type: :auth_status, is_authenticating: true}} = Parser.parse_message(data)
    end

    test "parses prompt_suggestion messages" do
      data = %{
        "type" => "prompt_suggestion",
        "suggestion" => "Add tests for the new module",
        "uuid" => "uuid-ps",
        "session_id" => "session-1"
      }

      assert {:ok, %PromptSuggestionMessage{type: :prompt_suggestion, suggestion: "Add tests for the new module"}} =
               Parser.parse_message(data)
    end

    test "parses status system messages" do
      data = %{
        "type" => "system",
        "subtype" => "status",
        "status" => "thinking",
        "permission_mode" => "default",
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %Status{status: "thinking", permission_mode: :default}} =
               Parser.parse_message(data)
    end

    test "parses local_command_output system messages" do
      data = %{
        "type" => "system",
        "subtype" => "local_command_output",
        "content" => "Cost: $0.50",
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %LocalCommandOutput{content: "Cost: $0.50"}} = Parser.parse_message(data)
    end

    test "parses files_persisted system messages" do
      data = %{
        "type" => "system",
        "subtype" => "files_persisted",
        "files" => [%{"filename" => "doc.txt", "file_id" => "file_abc"}],
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %FilesPersisted{files: [%{filename: "doc.txt", file_id: "file_abc"}]}} =
               Parser.parse_message(data)
    end

    test "parses elicitation_complete system messages" do
      data = %{
        "type" => "system",
        "subtype" => "elicitation_complete",
        "mcp_server_name" => "my-server",
        "elicitation_id" => "elicit-123",
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %ElicitationComplete{mcp_server_name: "my-server", elicitation_id: "elicit-123"}} =
               Parser.parse_message(data)
    end

    test "parses task_started system messages" do
      data = %{
        "type" => "system",
        "subtype" => "task_started",
        "task_id" => "task-1",
        "description" => "Running tests",
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %TaskStarted{task_id: "task-1", description: "Running tests"}} =
               Parser.parse_message(data)
    end

    test "parses task_progress system messages" do
      data = %{
        "type" => "system",
        "subtype" => "task_progress",
        "task_id" => "task-1",
        "description" => "Still running",
        "usage" => %{"total_tokens" => 1000, "tool_uses" => 5, "duration_ms" => 3000},
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %TaskProgress{task_id: "task-1"}} = Parser.parse_message(data)
    end

    test "parses task_notification system messages" do
      data = %{
        "type" => "system",
        "subtype" => "task_notification",
        "task_id" => "task-1",
        "status" => "completed",
        "output_file" => "/tmp/output.json",
        "summary" => "Done",
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %TaskNotification{task_id: "task-1", status: :completed}} =
               Parser.parse_message(data)
    end

    test "parses hook_progress system messages" do
      data = %{
        "type" => "system",
        "subtype" => "hook_progress",
        "hook_id" => "hook-1",
        "hook_name" => "my_hook",
        "hook_event" => "PreToolUse",
        "stdout" => "output",
        "stderr" => "",
        "output" => "output",
        "uuid" => "uuid-1",
        "session_id" => "session-1"
      }

      assert {:ok, %HookProgress{hook_id: "hook-1"}} = Parser.parse_message(data)
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
  # parse_messages/1
  # ============================================================================

  describe "parse_messages/1" do
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
          "permission_mode" => "default",
          "api_key_source" => "env",
          "slash_commands" => [],
          "output_style" => "default"
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

      assert {:ok, [%Init{}, %AssistantMessage{}, %CompactBoundary{}, %ResultMessage{}]} =
               Parser.parse_messages(data)
    end

    test "skips unknown message types" do
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
          "permission_mode" => "default",
          "api_key_source" => "env",
          "slash_commands" => [],
          "output_style" => "default"
        },
        %{"type" => "future_type", "data" => "something"},
        %{
          "type" => "result",
          "subtype" => "success",
          "uuid" => "result-uuid",
          "is_error" => false,
          "duration_ms" => 100,
          "duration_api_ms" => 90,
          "num_turns" => 1,
          "result" => "Done",
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

      assert {:ok, [%Init{}, %ResultMessage{}]} = Parser.parse_messages(data)
    end

    test "handles empty list" do
      assert {:ok, []} = Parser.parse_messages([])
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
      assert [%Init{}, %AssistantMessage{}, %CompactBoundary{}, %ResultMessage{}] = messages
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

    test "skips unknown message types in stream" do
      stream = """
      {"type":"system","subtype":"init","uuid":"550e8400-e29b-41d4-a716-446655440000","cwd":"/test","session_id":"123","tools":[],"mcp_servers":[],"model":"claude","permissionMode":"default","apiKeySource":"env","slashCommands":[],"outputStyle":"default"}
      {"type":"future_type","data":"something"}
      {"type":"result","subtype":"success","uuid":"result-uuid","is_error":false,"duration_ms":100,"duration_api_ms":90,"num_turns":1,"result":"Done","session_id":"123","total_cost_usd":0.001,"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1,"server_tool_use":{"web_search_requests":0}}}
      """

      assert {:ok, messages} = Parser.parse_stream(stream)
      assert [%Init{}, %ResultMessage{}] = messages
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

      assert [%Init{}, %AssistantMessage{}, %ResultMessage{}] = messages

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

    test "parses redacted_thinking content blocks" do
      data = %{"type" => "redacted_thinking", "data" => "encrypted_data_abc"}

      assert {:ok, %RedactedThinkingBlock{data: "encrypted_data_abc"}} = Parser.parse_content(data)
    end

    test "parses server_tool_use content blocks" do
      data = %{
        "type" => "server_tool_use",
        "id" => "srvtoolu_123",
        "name" => "web_search",
        "input" => %{"query" => "elixir"}
      }

      assert {:ok, %ServerToolUseBlock{id: "srvtoolu_123", name: :web_search}} = Parser.parse_content(data)
    end

    test "parses mcp_tool_use content blocks" do
      data = %{
        "type" => "mcp_tool_use",
        "id" => "mcptoolu_123",
        "name" => "read_file",
        "server_name" => "filesystem",
        "input" => %{"path" => "/tmp/test"}
      }

      assert {:ok, %MCPToolUseBlock{name: "read_file", server_name: "filesystem"}} = Parser.parse_content(data)
    end

    test "parses mcp_tool_result content blocks" do
      data = %{
        "type" => "mcp_tool_result",
        "tool_use_id" => "mcptoolu_123",
        "content" => "file contents",
        "is_error" => false
      }

      assert {:ok, %MCPToolResultBlock{tool_use_id: "mcptoolu_123", is_error: false}} = Parser.parse_content(data)
    end

    test "parses compaction content blocks" do
      data = %{"type" => "compaction", "content" => "Summary of prior context."}

      assert {:ok, %CompactionBlock{content: "Summary of prior context."}} = Parser.parse_content(data)
    end

    test "parses compaction content blocks with nil content" do
      data = %{"type" => "compaction", "content" => nil}

      assert {:ok, %CompactionBlock{content: nil}} = Parser.parse_content(data)
    end

    test "parses server tool result blocks via unified ServerToolResultBlock" do
      for type <- ~w(web_search_tool_result web_fetch_tool_result code_execution_tool_result
                     bash_code_execution_tool_result text_editor_code_execution_tool_result
                     tool_search_tool_result) do
        data = %{
          "type" => type,
          "tool_use_id" => "toolu_#{type}",
          "content" => [%{"type" => "result"}]
        }

        assert {:ok, %ServerToolResultBlock{tool_use_id: "toolu_" <> ^type}} =
                 Parser.parse_content(data)
      end
    end

    test "parses container_upload content blocks" do
      data = %{"type" => "container_upload", "file_id" => "file_abc123"}

      assert {:ok, %ContainerUploadBlock{file_id: "file_abc123"}} = Parser.parse_content(data)
    end

    test "returns error for unknown content type" do
      assert {:error, {:unknown_content_type, "unknown"}} = Parser.parse_content(%{"type" => "unknown"})
    end

    test "returns error for missing type" do
      assert {:error, :missing_type} = Parser.parse_content(%{"text" => "Hello"})
    end
  end

  # ============================================================================
  # parse_contents/1
  # ============================================================================

  describe "parse_contents/1" do
    test "parses a list of content blocks" do
      data = [
        %{"type" => "text", "text" => "I'll help you."},
        %{"type" => "tool_use", "id" => "123", "name" => "Read", "input" => %{}},
        %{"type" => "text", "text" => "Done!"}
      ]

      assert {:ok, [%TextBlock{}, %ToolUseBlock{}, %TextBlock{}]} = Parser.parse_contents(data)
    end

    test "skips unknown content types" do
      data = [
        %{"type" => "text", "text" => "OK"},
        %{"type" => "future_block", "data" => "something"},
        %{"type" => "text", "text" => "More"}
      ]

      assert {:ok, [%TextBlock{text: "OK"}, %TextBlock{text: "More"}]} = Parser.parse_contents(data)
    end

    test "handles empty list" do
      assert {:ok, []} = Parser.parse_contents([])
    end
  end

  # ============================================================================
  # normalize_keys/1
  # ============================================================================

  describe "normalize_keys/1" do
    test "converts camelCase keys to snake_case" do
      assert %{"session_id" => "123", "type" => "user"} =
               Parser.normalize_keys(%{"sessionId" => "123", "type" => "user"})
    end

    test "normalizes nested maps recursively" do
      input = %{"outerKey" => %{"innerKey" => "value"}}
      assert %{"outer_key" => %{"inner_key" => "value"}} = Parser.normalize_keys(input)
    end

    test "normalizes maps inside lists" do
      input = [%{"inputTokens" => 5}, %{"outputTokens" => 10}]
      assert [%{"input_tokens" => 5}, %{"output_tokens" => 10}] = Parser.normalize_keys(input)
    end

    test "preserves tool input parameter names (opaque keys)" do
      input = %{
        "name" => "Bash",
        "input" => %{"commandLine" => "echo hello", "userFlag" => true}
      }

      result = Parser.normalize_keys(input)

      assert result["name"] == "Bash"
      # input map contents must NOT be normalized
      assert result["input"] == %{"commandLine" => "echo hello", "userFlag" => true}
    end

    test "preserves tool_input parameter names (opaque keys)" do
      input = %{
        "toolInput" => %{"myParam" => "value"}
      }

      result = Parser.normalize_keys(input)

      # key itself is normalized, but contents are not
      assert result["tool_input"] == %{"myParam" => "value"}
    end

    test "passes through non-map non-list values unchanged" do
      assert Parser.normalize_keys("hello") == "hello"
      assert Parser.normalize_keys(42) == 42
      assert Parser.normalize_keys(nil) == nil
    end
  end
end
