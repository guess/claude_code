defmodule ClaudeCode.JSONEncoderTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.AuthStatusMessage
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.ToolProgressMessage
  alias ClaudeCode.Message.ToolUseSummaryMessage
  alias ClaudeCode.Message.UserMessage

  describe "to_encodable/1" do
    test "excludes nil values from output" do
      block = %TextBlock{type: :text, text: "hello"}
      result = ClaudeCode.JSONEncoder.to_encodable(block)

      assert result == %{type: :text, text: "hello"}
      refute Map.has_key?(result, :some_nil_field)
    end

    test "recursively processes nested structs" do
      content = [%TextBlock{type: :text, text: "hello"}]

      message = %AssistantMessage{
        type: :assistant,
        session_id: "sess_123",
        uuid: nil,
        parent_tool_use_id: nil,
        message: %{
          content: content,
          role: :assistant
        }
      }

      result = ClaudeCode.JSONEncoder.to_encodable(message)

      assert result.type == :assistant
      assert result.session_id == "sess_123"
      refute Map.has_key?(result, :uuid)
      refute Map.has_key?(result, :parent_tool_use_id)
      assert [%{type: :text, text: "hello"}] = result.message.content
    end

    test "processes lists with nested structs" do
      blocks = [
        %TextBlock{type: :text, text: "hello"},
        %TextBlock{type: :text, text: "world"}
      ]

      result = Enum.map(blocks, &ClaudeCode.JSONEncoder.to_encodable/1)

      assert result == [
               %{type: :text, text: "hello"},
               %{type: :text, text: "world"}
             ]
    end
  end

  describe "Jason.Encoder for content blocks" do
    test "encodes TextBlock" do
      block = %TextBlock{type: :text, text: "hello"}
      json = Jason.encode!(block)

      assert json =~ ~s("type":"text")
      assert json =~ ~s("text":"hello")
    end

    test "encodes ThinkingBlock" do
      block = %ThinkingBlock{type: :thinking, thinking: "reasoning...", signature: "sig_123"}
      json = Jason.encode!(block)

      assert json =~ ~s("type":"thinking")
      assert json =~ ~s("thinking":"reasoning...")
      assert json =~ ~s("signature":"sig_123")
    end

    test "encodes ToolUseBlock" do
      block = %ToolUseBlock{type: :tool_use, id: "tool_1", name: "Read", input: %{path: "/test"}}
      json = Jason.encode!(block)

      assert json =~ ~s("type":"tool_use")
      assert json =~ ~s("id":"tool_1")
      assert json =~ ~s("name":"Read")
      assert json =~ "\"input\""
      assert json =~ ~s("path":"/test")
    end

    test "encodes ToolResultBlock with string content" do
      block = %ToolResultBlock{
        type: :tool_result,
        tool_use_id: "tool_1",
        content: "file contents",
        is_error: false
      }

      json = Jason.encode!(block)

      assert json =~ ~s("type":"tool_result")
      assert json =~ ~s("tool_use_id":"tool_1")
      assert json =~ ~s("content":"file contents")
      assert json =~ "\"is_error\":false"
    end

    test "encodes ToolResultBlock with nested content blocks" do
      block = %ToolResultBlock{
        type: :tool_result,
        tool_use_id: "tool_1",
        content: [%TextBlock{type: :text, text: "result text"}],
        is_error: false
      }

      json = Jason.encode!(block)

      assert json =~ ~s("type":"tool_result")
      assert json =~ "\"content\":"
      # Nested TextBlock should be encoded
      decoded = Jason.decode!(json)
      assert [%{"type" => "text", "text" => "result text"}] = decoded["content"]
    end
  end

  describe "Jason.Encoder for message types" do
    test "encodes SystemMessage" do
      message = %SystemMessage{
        type: :system,
        subtype: :init,
        uuid: "uuid_123",
        cwd: "/home/user",
        session_id: "sess_123",
        tools: ["Read", "Write"],
        mcp_servers: [%{name: "test", status: "connected"}],
        model: "claude-sonnet-4-20250514",
        permission_mode: :default,
        api_key_source: "env",
        claude_code_version: nil,
        slash_commands: [],
        output_style: "default",
        agents: [],
        skills: [],
        plugins: []
      }

      json = Jason.encode!(message)

      assert json =~ ~s("type":"system")
      assert json =~ ~s("subtype":"init")
      assert json =~ ~s("session_id":"sess_123")
      refute json =~ "\"claude_code_version\""
    end

    test "encodes AssistantMessage with nested content" do
      message = %AssistantMessage{
        type: :assistant,
        session_id: "sess_123",
        uuid: "uuid_456",
        parent_tool_use_id: nil,
        message: %{
          id: "msg_1",
          type: :message,
          role: :assistant,
          content: [%TextBlock{type: :text, text: "Hello!"}],
          model: "claude-sonnet-4-20250514",
          stop_reason: :end_turn,
          stop_sequence: nil,
          usage: %{input_tokens: 10, output_tokens: 5}
        }
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "assistant"
      assert decoded["session_id"] == "sess_123"
      assert decoded["uuid"] == "uuid_456"
      refute Map.has_key?(decoded, "parent_tool_use_id")
      assert [%{"type" => "text", "text" => "Hello!"}] = decoded["message"]["content"]
    end

    test "encodes UserMessage" do
      message = %UserMessage{
        type: :user,
        session_id: "sess_123",
        uuid: nil,
        parent_tool_use_id: nil,
        message: %{
          content: "Hello Claude",
          role: :user
        }
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "user"
      assert decoded["session_id"] == "sess_123"
      refute Map.has_key?(decoded, "uuid")
    end

    test "encodes ResultMessage excluding nil fields" do
      message = %ResultMessage{
        type: :result,
        subtype: :success,
        is_error: false,
        duration_ms: 1500.0,
        duration_api_ms: 1200.0,
        num_turns: 1,
        result: "Done!",
        session_id: "sess_123",
        total_cost_usd: 0.001,
        usage: %{input_tokens: 100, output_tokens: 50},
        uuid: nil,
        model_usage: nil,
        permission_denials: nil,
        structured_output: nil,
        errors: nil
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "result"
      assert decoded["result"] == "Done!"
      assert decoded["is_error"] == false
      refute Map.has_key?(decoded, "uuid")
      refute Map.has_key?(decoded, "model_usage")
      refute Map.has_key?(decoded, "errors")
    end

    test "encodes PartialAssistantMessage" do
      message = %PartialAssistantMessage{
        type: :stream_event,
        event: %{
          type: :content_block_delta,
          index: 0,
          delta: %{type: :text_delta, text: "Hi"}
        },
        session_id: "sess_123",
        parent_tool_use_id: nil,
        uuid: "uuid_789"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "stream_event"
      assert decoded["event"]["type"] == "content_block_delta"
      assert decoded["event"]["delta"]["text"] == "Hi"
      refute Map.has_key?(decoded, "parent_tool_use_id")
    end

    test "encodes CompactBoundaryMessage" do
      message = %CompactBoundaryMessage{
        type: :system,
        subtype: :compact_boundary,
        uuid: "uuid_123",
        session_id: "sess_123",
        compact_metadata: %{trigger: "auto", pre_tokens: 5000}
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "system"
      assert decoded["subtype"] == "compact_boundary"
      assert decoded["compact_metadata"]["trigger"] == "auto"
      assert decoded["compact_metadata"]["pre_tokens"] == 5000
    end

    test "encodes RateLimitEvent" do
      message = %RateLimitEvent{
        type: :rate_limit_event,
        rate_limit_info: %{
          status: :allowed_warning,
          resets_at: 1_700_000_000_000,
          utilization: 0.85
        },
        uuid: "uuid_123",
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "rate_limit_event"
      assert decoded["rate_limit_info"]["status"] == "allowed_warning"
      assert decoded["rate_limit_info"]["resets_at"] == 1_700_000_000_000
      assert decoded["rate_limit_info"]["utilization"] == 0.85
      refute Map.has_key?(decoded, "uuid") == false
    end

    test "encodes RateLimitEvent excluding nil fields" do
      message = %RateLimitEvent{
        type: :rate_limit_event,
        rate_limit_info: %{status: :allowed, resets_at: nil, utilization: nil},
        uuid: nil,
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "rate_limit_event"
      refute Map.has_key?(decoded, "uuid")
    end

    test "encodes ToolProgressMessage" do
      message = %ToolProgressMessage{
        type: :tool_progress,
        tool_use_id: "toolu_abc123",
        tool_name: "Bash",
        parent_tool_use_id: "toolu_parent",
        elapsed_time_seconds: 5.2,
        uuid: "uuid_123",
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "tool_progress"
      assert decoded["tool_use_id"] == "toolu_abc123"
      assert decoded["tool_name"] == "Bash"
      assert decoded["parent_tool_use_id"] == "toolu_parent"
      assert decoded["elapsed_time_seconds"] == 5.2
    end

    test "encodes ToolProgressMessage excluding nil fields" do
      message = %ToolProgressMessage{
        type: :tool_progress,
        tool_use_id: "toolu_abc123",
        tool_name: "Bash",
        parent_tool_use_id: nil,
        elapsed_time_seconds: nil,
        task_id: nil,
        uuid: nil,
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "parent_tool_use_id")
      refute Map.has_key?(decoded, "elapsed_time_seconds")
      refute Map.has_key?(decoded, "task_id")
      refute Map.has_key?(decoded, "uuid")
    end

    test "encodes ToolUseSummaryMessage" do
      message = %ToolUseSummaryMessage{
        type: :tool_use_summary,
        summary: "Read 3 files and edited 1 file",
        preceding_tool_use_ids: ["toolu_abc", "toolu_def"],
        uuid: "uuid_123",
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "tool_use_summary"
      assert decoded["summary"] == "Read 3 files and edited 1 file"
      assert decoded["preceding_tool_use_ids"] == ["toolu_abc", "toolu_def"]
    end

    test "encodes AuthStatusMessage" do
      message = %AuthStatusMessage{
        type: :auth_status,
        is_authenticating: true,
        output: ["Authenticating...", "Waiting for response"],
        error: nil,
        uuid: "uuid_123",
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "auth_status"
      assert decoded["is_authenticating"] == true
      assert decoded["output"] == ["Authenticating...", "Waiting for response"]
      refute Map.has_key?(decoded, "error")
    end

    test "encodes AuthStatusMessage with error" do
      message = %AuthStatusMessage{
        type: :auth_status,
        is_authenticating: false,
        output: [],
        error: "Invalid API key",
        uuid: nil,
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["is_authenticating"] == false
      assert decoded["error"] == "Invalid API key"
      refute Map.has_key?(decoded, "uuid")
    end

    test "encodes PromptSuggestionMessage" do
      message = %PromptSuggestionMessage{
        type: :prompt_suggestion,
        suggestion: "Now add tests for the new function",
        uuid: "uuid_123",
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "prompt_suggestion"
      assert decoded["suggestion"] == "Now add tests for the new function"
    end

    test "encodes PromptSuggestionMessage excluding nil fields" do
      message = %PromptSuggestionMessage{
        type: :prompt_suggestion,
        suggestion: "Run the tests",
        uuid: nil,
        session_id: "sess_123"
      }

      json = Jason.encode!(message)
      decoded = Jason.decode!(json)

      refute Map.has_key?(decoded, "uuid")
    end
  end

  describe "JSON.Encoder (Elixir built-in)" do
    test "encodes TextBlock" do
      block = %TextBlock{type: :text, text: "hello"}
      json = JSON.encode!(block)

      assert json =~ "\"type\":"
      assert json =~ "\"text\":"
    end

    test "encodes ThinkingBlock" do
      block = %ThinkingBlock{type: :thinking, thinking: "reasoning...", signature: "sig_123"}
      json = JSON.encode!(block)

      assert json =~ "\"thinking\":"
      assert json =~ "\"signature\":"
    end

    test "encodes ToolUseBlock" do
      block = %ToolUseBlock{type: :tool_use, id: "tool_1", name: "Read", input: %{}}
      json = JSON.encode!(block)

      assert json =~ "\"id\":"
      assert json =~ "\"name\":"
    end

    test "encodes ToolResultBlock" do
      block = %ToolResultBlock{
        type: :tool_result,
        tool_use_id: "tool_1",
        content: "result",
        is_error: false
      }

      json = JSON.encode!(block)

      assert json =~ "\"tool_use_id\":"
      assert json =~ "\"is_error\":"
    end

    test "encodes AssistantMessage" do
      message = %AssistantMessage{
        type: :assistant,
        session_id: "sess_123",
        uuid: nil,
        parent_tool_use_id: nil,
        message: %{content: [], role: :assistant}
      }

      json = JSON.encode!(message)

      assert json =~ "\"type\":"
      assert json =~ "\"session_id\":"
    end

    test "encodes ResultMessage" do
      message = %ResultMessage{
        type: :result,
        subtype: :success,
        is_error: false,
        duration_ms: 1000.0,
        duration_api_ms: 800.0,
        num_turns: 1,
        result: "OK",
        session_id: "sess_123",
        total_cost_usd: 0.001,
        usage: %{input_tokens: 10, output_tokens: 5},
        uuid: nil,
        model_usage: nil,
        permission_denials: nil,
        structured_output: nil,
        errors: nil
      }

      json = JSON.encode!(message)

      assert json =~ "\"result\":"
      assert json =~ "\"is_error\":"
    end

    test "encodes RateLimitEvent" do
      message = %RateLimitEvent{
        type: :rate_limit_event,
        rate_limit_info: %{status: :allowed_warning, resets_at: 1_700_000_000_000, utilization: 0.85},
        session_id: "sess_123"
      }

      json = JSON.encode!(message)

      assert json =~ "\"rate_limit_info\":"
      assert json =~ "\"type\":"
    end

    test "encodes ToolProgressMessage" do
      message = %ToolProgressMessage{
        type: :tool_progress,
        tool_use_id: "toolu_abc",
        tool_name: "Bash",
        session_id: "sess_123"
      }

      json = JSON.encode!(message)

      assert json =~ "\"tool_use_id\":"
      assert json =~ "\"tool_name\":"
    end

    test "encodes ToolUseSummaryMessage" do
      message = %ToolUseSummaryMessage{
        type: :tool_use_summary,
        summary: "Read 3 files",
        session_id: "sess_123"
      }

      json = JSON.encode!(message)

      assert json =~ "\"summary\":"
      assert json =~ "\"type\":"
    end

    test "encodes AuthStatusMessage" do
      message = %AuthStatusMessage{
        type: :auth_status,
        is_authenticating: true,
        session_id: "sess_123"
      }

      json = JSON.encode!(message)

      assert json =~ "\"is_authenticating\":"
      assert json =~ "\"type\":"
    end

    test "encodes PromptSuggestionMessage" do
      message = %PromptSuggestionMessage{
        type: :prompt_suggestion,
        suggestion: "Add tests",
        session_id: "sess_123"
      }

      json = JSON.encode!(message)

      assert json =~ "\"suggestion\":"
      assert json =~ "\"type\":"
    end
  end

  describe "round-trip encoding" do
    test "TextBlock survives JSON round-trip" do
      original = %TextBlock{type: :text, text: "hello world"}

      decoded =
        original
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["type"] == "text"
      assert decoded["text"] == "hello world"
    end

    test "complex nested message survives round-trip" do
      original = %AssistantMessage{
        type: :assistant,
        session_id: "sess_123",
        uuid: "uuid_456",
        parent_tool_use_id: nil,
        message: %{
          content: [
            %TextBlock{type: :text, text: "Let me help"},
            %ToolUseBlock{type: :tool_use, id: "t1", name: "Read", input: %{path: "/test.txt"}}
          ],
          role: :assistant
        }
      }

      decoded =
        original
        |> Jason.encode!()
        |> Jason.decode!()

      assert decoded["type"] == "assistant"
      assert length(decoded["message"]["content"]) == 2

      [text_block, tool_block] = decoded["message"]["content"]
      assert text_block["type"] == "text"
      assert text_block["text"] == "Let me help"
      assert tool_block["type"] == "tool_use"
      assert tool_block["name"] == "Read"
    end
  end

  describe "pretty printing" do
    test "Jason supports pretty option" do
      block = %TextBlock{type: :text, text: "hello"}
      json = Jason.encode!(block, pretty: true)

      # Pretty printed JSON has newlines
      assert json =~ "\n"
    end

    @tag :skip
    test "JSON supports formatter" do
      # JSON.Formatter is not available in all Elixir versions
      # The built-in JSON module doesn't have a formatter yet
      block = %TextBlock{type: :text, text: "hello"}
      json = JSON.encode!(block)

      # Just verify encoding works
      assert json =~ "text"
    end
  end

  describe "String.Chars protocol" do
    test "TextBlock returns text" do
      block = %TextBlock{type: :text, text: "Hello world"}
      assert to_string(block) == "Hello world"
      assert "#{block}" == "Hello world"
    end

    test "ThinkingBlock returns thinking" do
      block = %ThinkingBlock{type: :thinking, thinking: "Let me think...", signature: "sig"}
      assert to_string(block) == "Let me think..."
    end

    test "AssistantMessage concatenates text blocks" do
      message = %AssistantMessage{
        type: :assistant,
        session_id: "sess_123",
        uuid: nil,
        parent_tool_use_id: nil,
        message: %{
          content: [
            %TextBlock{type: :text, text: "Hello "},
            %ToolUseBlock{type: :tool_use, id: "t1", name: "Read", input: %{}},
            %TextBlock{type: :text, text: "world!"}
          ],
          role: :assistant
        }
      }

      assert to_string(message) == "Hello world!"
    end

    test "AssistantMessage with no text blocks returns empty string" do
      message = %AssistantMessage{
        type: :assistant,
        session_id: "sess_123",
        uuid: nil,
        parent_tool_use_id: nil,
        message: %{
          content: [
            %ToolUseBlock{type: :tool_use, id: "t1", name: "Read", input: %{}}
          ],
          role: :assistant
        }
      }

      assert to_string(message) == ""
    end

    test "PartialAssistantMessage returns text delta" do
      message = %PartialAssistantMessage{
        type: :stream_event,
        event: %{
          type: :content_block_delta,
          index: 0,
          delta: %{type: :text_delta, text: "Hi"}
        },
        session_id: "sess_123",
        parent_tool_use_id: nil,
        uuid: nil
      }

      assert to_string(message) == "Hi"
    end

    test "PartialAssistantMessage with non-text delta returns empty string" do
      message = %PartialAssistantMessage{
        type: :stream_event,
        event: %{
          type: :content_block_delta,
          index: 0,
          delta: %{type: :input_json_delta, partial_json: "{"}
        },
        session_id: "sess_123",
        parent_tool_use_id: nil,
        uuid: nil
      }

      assert to_string(message) == ""
    end

    test "PartialAssistantMessage with message_start returns empty string" do
      message = %PartialAssistantMessage{
        type: :stream_event,
        event: %{type: :message_start, message: %{}},
        session_id: "sess_123",
        parent_tool_use_id: nil,
        uuid: nil
      }

      assert to_string(message) == ""
    end
  end
end
