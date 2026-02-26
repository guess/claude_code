defmodule ClaudeCode.Test.Factory do
  @moduledoc """
  Test factories for ClaudeCode structs.

  Provides simple factory functions with sensible defaults that accept
  keyword lists or maps for overrides.

  ## Usage

      import ClaudeCode.Test.Factory

      # Create with defaults
      text_block()

      # Override with keywords
      text_block(text: "custom text")

      # Override with map
      text_block(%{text: "custom text"})

      # Compose factories
      assistant_message(message: %{content: [text_block(text: "Hello")]})
  """

  alias ClaudeCode.Agent
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

  # ============================================================================
  # Agents
  # ============================================================================

  @doc """
  Creates an Agent with default values.

      agent()
      agent(name: "debugger", tools: ["Bash", "Read"])
      agent(permission_mode: :plan, memory: :project)
  """
  def agent(attrs \\ []) do
    name = Keyword.get(attrs, :name, "test-agent-#{unique_id()}")
    attrs = Keyword.put(attrs, :name, name)
    Agent.new(attrs)
  end

  # ============================================================================
  # Content Blocks
  # ============================================================================

  @doc """
  Creates a TextBlock with default text.

      text_block()
      text_block(text: "custom text")
  """
  def text_block(attrs \\ []) do
    merge(%TextBlock{type: :text, text: "sample text"}, attrs)
  end

  @doc """
  Creates a ToolUseBlock with default values.

      tool_use_block()
      tool_use_block(name: "Bash", input: %{command: "ls"})
  """
  def tool_use_block(attrs \\ []) do
    merge(
      %ToolUseBlock{type: :tool_use, id: "toolu_#{unique_id()}", name: "Read", input: %{"path" => "/tmp/test.txt"}},
      attrs
    )
  end

  @doc """
  Creates a ToolResultBlock with default values.

      tool_result_block()
      tool_result_block(content: "file contents", is_error: false)
  """
  def tool_result_block(attrs \\ []) do
    merge(
      %ToolResultBlock{
        type: :tool_result,
        tool_use_id: "toolu_#{unique_id()}",
        content: "result content",
        is_error: false
      },
      attrs
    )
  end

  @doc """
  Creates a ThinkingBlock with default values.

      thinking_block()
      thinking_block(thinking: "Let me analyze this...")
  """
  def thinking_block(attrs \\ []) do
    merge(%ThinkingBlock{type: :thinking, thinking: "reasoning content", signature: "sig_#{unique_id()}"}, attrs)
  end

  # ============================================================================
  # Content Blocks (Positional Arg Variants)
  # ============================================================================

  @doc """
  Creates a TextBlock with the given text.

      text_content("Hello world")
  """
  def text_content(text) do
    text_block(text: text)
  end

  @doc """
  Creates a ToolUseBlock with positional arguments.

      tool_use_content("Read", %{path: "/tmp/file.txt"})
      tool_use_content("Read", %{path: "/tmp/file.txt"}, "tool_123")
  """
  def tool_use_content(name, input, id \\ nil) do
    tool_use_block(
      name: name,
      input: input,
      id: id || "toolu_#{unique_id()}"
    )
  end

  @doc """
  Creates a ToolResultBlock with positional arguments.

      tool_result_content("file contents")
      tool_result_content("file contents", "tool_123")
      tool_result_content("error message", "tool_123", true)
  """
  def tool_result_content(content, tool_use_id \\ nil, is_error \\ false) do
    tool_result_block(
      content: content,
      tool_use_id: tool_use_id || "toolu_#{unique_id()}",
      is_error: is_error
    )
  end

  @doc """
  Creates a ThinkingBlock with positional arguments.

      thinking_content("Let me reason through this...")
      thinking_content("Reasoning...", "sig_abc123")
  """
  def thinking_content(thinking, signature \\ nil) do
    thinking_block(
      thinking: thinking,
      signature: signature || "sig_#{unique_id()}"
    )
  end

  # ============================================================================
  # Messages
  # ============================================================================

  @doc """
  Creates a SystemMessage with default values.

      system_message()
      system_message(model: "claude-opus-4-20250514")
  """
  def system_message(attrs \\ []) do
    merge(
      %SystemMessage{
        type: :system,
        subtype: :init,
        uuid: uuid(),
        model: "claude-sonnet-4-20250514",
        session_id: session_id(),
        cwd: "/test",
        tools: [],
        mcp_servers: [],
        permission_mode: :default,
        api_key_source: "ANTHROPIC_API_KEY",
        slash_commands: [],
        output_style: "default"
      },
      attrs
    )
  end

  @doc """
  Creates a CompactBoundaryMessage with default values.

      compact_boundary_message()
      compact_boundary_message(compact_metadata: %{trigger: "auto", pre_tokens: 5000})
  """
  def compact_boundary_message(attrs \\ []) do
    merge(
      %CompactBoundaryMessage{
        type: :system,
        subtype: :compact_boundary,
        uuid: uuid(),
        session_id: session_id(),
        compact_metadata: %{trigger: "manual", pre_tokens: 1000}
      },
      attrs
    )
  end

  @doc """
  Creates an AssistantMessage with default values.

  The nested `message` field can be overridden with a map.

      assistant_message()
      assistant_message(message: %{content: [text_block()]})
      assistant_message(session_id: "custom-session")
  """
  def assistant_message(attrs \\ []) do
    attrs = to_map(attrs)

    message_defaults = %{
      id: "msg_#{unique_id()}",
      type: :message,
      role: :assistant,
      model: "claude-sonnet-4-20250514",
      content: [text_block()],
      stop_reason: nil,
      stop_sequence: nil,
      usage: default_usage()
    }

    message_attrs = Map.get(attrs, :message, %{})
    merged_message = Map.merge(message_defaults, to_map(message_attrs))

    merge(
      %AssistantMessage{
        type: :assistant,
        session_id: session_id(),
        uuid: nil,
        parent_tool_use_id: nil,
        message: merged_message
      },
      Map.delete(attrs, :message)
    )
  end

  @doc """
  Creates a UserMessage with default values.

      user_message()
      user_message(message: %{content: [tool_result_block()]})
  """
  def user_message(attrs \\ []) do
    attrs = to_map(attrs)

    message_defaults = %{
      role: :user,
      content: [text_block()]
    }

    message_attrs = Map.get(attrs, :message, %{})
    merged_message = Map.merge(message_defaults, to_map(message_attrs))

    merge(
      %UserMessage{type: :user, session_id: session_id(), uuid: nil, parent_tool_use_id: nil, message: merged_message},
      Map.delete(attrs, :message)
    )
  end

  @doc """
  Creates a ResultMessage with default values.

      result_message()
      result_message(result: "Task completed", is_error: false)
      result_message(is_error: true, subtype: :error_during_execution)
  """
  def result_message(attrs \\ []) do
    merge(
      %ResultMessage{
        type: :result,
        subtype: :success,
        is_error: false,
        duration_ms: 100.0,
        duration_api_ms: 80.0,
        num_turns: 1,
        result: "Done",
        session_id: session_id(),
        total_cost_usd: 0.001,
        usage: %{},
        uuid: nil,
        model_usage: nil,
        permission_denials: nil,
        structured_output: nil,
        errors: nil
      },
      attrs
    )
  end

  @doc """
  Creates a RateLimitEvent with default values.

      rate_limit_event()
      rate_limit_event(rate_limit_info: %{status: :rejected, resets_at: 1_700_000_060_000})
  """
  def rate_limit_event(attrs \\ []) do
    merge(
      %RateLimitEvent{
        type: :rate_limit_event,
        rate_limit_info: %{status: :allowed, resets_at: nil, utilization: nil},
        uuid: uuid(),
        session_id: session_id()
      },
      attrs
    )
  end

  @doc """
  Creates a ToolProgressMessage with default values.

      tool_progress_message()
      tool_progress_message(tool_name: "Bash", elapsed_time_seconds: 5.2)
  """
  def tool_progress_message(attrs \\ []) do
    merge(
      %ToolProgressMessage{
        type: :tool_progress,
        tool_use_id: "toolu_#{unique_id()}",
        tool_name: "Read",
        parent_tool_use_id: nil,
        elapsed_time_seconds: 1.0,
        task_id: nil,
        uuid: uuid(),
        session_id: session_id()
      },
      attrs
    )
  end

  @doc """
  Creates a ToolUseSummaryMessage with default values.

      tool_use_summary_message()
      tool_use_summary_message(summary: "Read 3 files")
  """
  def tool_use_summary_message(attrs \\ []) do
    merge(
      %ToolUseSummaryMessage{
        type: :tool_use_summary,
        summary: "Read 1 file",
        preceding_tool_use_ids: [],
        uuid: uuid(),
        session_id: session_id()
      },
      attrs
    )
  end

  @doc """
  Creates an AuthStatusMessage with default values.

      auth_status_message()
      auth_status_message(is_authenticating: false, error: "Invalid key")
  """
  def auth_status_message(attrs \\ []) do
    merge(
      %AuthStatusMessage{
        type: :auth_status,
        is_authenticating: true,
        output: [],
        error: nil,
        uuid: uuid(),
        session_id: session_id()
      },
      attrs
    )
  end

  @doc """
  Creates a PromptSuggestionMessage with default values.

      prompt_suggestion_message()
      prompt_suggestion_message(suggestion: "Run the tests")
  """
  def prompt_suggestion_message(attrs \\ []) do
    merge(
      %PromptSuggestionMessage{
        type: :prompt_suggestion,
        suggestion: "Add tests for the new module",
        uuid: uuid(),
        session_id: session_id()
      },
      attrs
    )
  end

  # ============================================================================
  # Stream Events (Partial Messages)
  # ============================================================================

  @doc """
  Creates a PartialAssistantMessage (stream event) with default values.

      partial_message()
      partial_message(event: %{type: :content_block_delta, delta: %{type: :text_delta, text: "Hi"}})
  """
  def partial_message(attrs \\ []) do
    merge(
      %PartialAssistantMessage{
        type: :stream_event,
        event: %{type: :message_start, message: %{}},
        session_id: session_id(),
        parent_tool_use_id: nil,
        uuid: uuid()
      },
      attrs
    )
  end

  @doc """
  Creates a message_start stream event.

      stream_event_message_start()
      stream_event_message_start(%{message: %{id: "msg_123"}})
  """
  def stream_event_message_start(attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{
        type: :message_start,
        message: Map.get(attrs, :message, %{})
      },
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates a content_block_start stream event.

      stream_event_content_block_start()
      stream_event_content_block_start(%{index: 0, content_block: %{type: :text, text: ""}})
  """
  def stream_event_content_block_start(attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{
        type: :content_block_start,
        index: Map.get(attrs, :index, 0),
        content_block: Map.get(attrs, :content_block, %{type: :text, text: ""})
      },
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates a text delta stream event.

      stream_event_text_delta("Hello")
      stream_event_text_delta("world", %{index: 0})
  """
  def stream_event_text_delta(text, attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{
        type: :content_block_delta,
        index: Map.get(attrs, :index, 0),
        delta: %{type: :text_delta, text: text}
      },
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates an input_json_delta stream event for tool use streaming.

      stream_event_input_json_delta("{\"path\":")
      stream_event_input_json_delta("\"/test.txt\"}", %{index: 1})
  """
  def stream_event_input_json_delta(partial_json, attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{
        type: :content_block_delta,
        index: Map.get(attrs, :index, 0),
        delta: %{type: :input_json_delta, partial_json: partial_json}
      },
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates a thinking_delta stream event for extended thinking streaming.

      stream_event_thinking_delta("Let me reason...")
      stream_event_thinking_delta("more reasoning", %{index: 0})
  """
  def stream_event_thinking_delta(thinking, attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{
        type: :content_block_delta,
        index: Map.get(attrs, :index, 0),
        delta: %{type: :thinking_delta, thinking: thinking}
      },
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates a content_block_stop stream event.

      stream_event_content_block_stop()
      stream_event_content_block_stop(%{index: 0})
  """
  def stream_event_content_block_stop(attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{
        type: :content_block_stop,
        index: Map.get(attrs, :index, 0)
      },
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates a message_delta stream event.

      stream_event_message_delta()
      stream_event_message_delta(%{delta: %{stop_reason: "end_turn"}})
  """
  def stream_event_message_delta(attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{
        type: :message_delta,
        delta: Map.get(attrs, :delta, %{stop_reason: "end_turn"}),
        usage: Map.get(attrs, :usage, %{})
      },
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates a message_stop stream event.

      stream_event_message_stop()
  """
  def stream_event_message_stop(attrs \\ %{}) do
    attrs = to_map(attrs)

    %PartialAssistantMessage{
      type: :stream_event,
      event: %{type: :message_stop},
      session_id: Map.get(attrs, :session_id, session_id()),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, uuid())
    }
  end

  @doc """
  Creates a complete sequence of stream events simulating a text response.

      stream_event_sequence(["Hello", " ", "World!"])
  """
  def stream_event_sequence(text_chunks) when is_list(text_chunks) do
    text_deltas = Enum.map(text_chunks, &stream_event_text_delta/1)

    [stream_event_message_start()] ++
      [stream_event_content_block_start()] ++
      text_deltas ++
      [stream_event_content_block_stop()] ++
      [stream_event_message_delta()] ++
      [stream_event_message_stop()]
  end

  # Legacy aliases for backward compatibility
  @doc false
  def text_delta(text, attrs) when is_list(attrs) do
    stream_event_text_delta(text, Map.new(attrs))
  end

  def text_delta(text) do
    stream_event_text_delta(text)
  end

  @doc false
  def thinking_delta(thinking, attrs) when is_list(attrs) do
    stream_event_thinking_delta(thinking, Map.new(attrs))
  end

  def thinking_delta(thinking) do
    stream_event_thinking_delta(thinking)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp merge(struct, attrs) when is_list(attrs), do: struct!(struct, attrs)
  defp merge(struct, attrs) when is_map(attrs), do: struct!(struct, Map.to_list(attrs))

  defp to_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp to_map(attrs) when is_map(attrs), do: attrs

  # ============================================================================
  # ID Generators (public for use by ClaudeCode.Test)
  # ============================================================================

  @doc "Generates a unique numeric ID"
  def unique_id, do: :rand.uniform(999_999)

  @doc "Generates a test session ID"
  def generate_session_id, do: "test-#{unique_id()}"

  @doc "Generates a test message ID"
  def generate_message_id, do: "msg_test_#{unique_id()}"

  @doc "Generates a test tool ID"
  def generate_tool_id, do: "toolu_test_#{unique_id()}"

  @doc "Generates a test signature"
  def generate_signature, do: "sig_test_#{unique_id()}"

  @doc "Generates a test UUID"
  def generate_uuid, do: "#{unique_id()}-#{unique_id()}-#{unique_id()}"

  # Internal aliases for backward compatibility within this module
  defp session_id, do: generate_session_id()
  defp uuid, do: generate_uuid()

  @doc "Returns default usage map for messages"
  def default_usage do
    %{
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: nil,
      cache_read_input_tokens: nil,
      server_tool_use: nil
    }
  end
end
