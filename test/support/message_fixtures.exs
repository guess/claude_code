defmodule ClaudeCode.Test.MessageFixtures do
  @moduledoc """
  Test fixtures for creating properly structured messages.
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Message
  alias ClaudeCode.Message.StreamEvent

  def system_message(attrs \\ %{}) do
    defaults = %{
      type: "system",
      subtype: "init",
      uuid: "550e8400-e29b-41d4-a716-446655440000",
      model: "claude-3",
      session_id: "test-123",
      cwd: "/test",
      tools: [],
      mcp_servers: [],
      permission_mode: "auto",
      api_key_source: "ANTHROPIC_API_KEY",
      slash_commands: [],
      output_style: "default",
      compact_metadata: nil
    }

    struct!(Message.System, Map.merge(defaults, attrs))
  end

  def system_message_compact_boundary(attrs \\ %{}) do
    defaults = %{
      type: "system",
      subtype: "compact_boundary",
      uuid: "550e8400-e29b-41d4-a716-446655440000",
      session_id: "test-123",
      compact_metadata: %{trigger: "manual", pre_tokens: 1000},
      cwd: nil,
      tools: nil,
      mcp_servers: nil,
      model: nil,
      permission_mode: nil,
      api_key_source: nil,
      slash_commands: nil,
      output_style: nil
    }

    struct!(Message.System, Map.merge(defaults, attrs))
  end

  def assistant_message(attrs \\ %{}) do
    attrs = Map.new(attrs)

    message_defaults = %{
      id: "msg_#{:rand.uniform(1000)}",
      type: "message",
      role: "assistant",
      model: "claude-3",
      content: [],
      stop_reason: nil,
      stop_sequence: nil,
      usage: %{}
    }

    defaults = %{
      type: "assistant",
      session_id: "test-123",
      uuid: nil,
      parent_tool_use_id: nil,
      message: Map.merge(message_defaults, Map.get(attrs, :message, %{}))
    }

    struct!(Message.Assistant, Map.merge(defaults, Map.delete(attrs, :message)))
  end

  def user_message(attrs \\ %{}) do
    attrs = Map.new(attrs)

    message_defaults = %{
      id: "msg_#{:rand.uniform(1000)}",
      type: "message",
      role: "user",
      content: []
    }

    defaults = %{
      type: "user",
      session_id: "test-123",
      uuid: nil,
      parent_tool_use_id: nil,
      message: Map.merge(message_defaults, Map.get(attrs, :message, %{}))
    }

    struct!(Message.User, Map.merge(defaults, Map.delete(attrs, :message)))
  end

  def result_message(attrs \\ %{}) do
    defaults = %{
      type: "result",
      subtype: :success,
      is_error: false,
      duration_ms: 100,
      duration_api_ms: 80,
      num_turns: 1,
      result: "Done",
      session_id: "test-123",
      total_cost_usd: 0.001,
      usage: %{},
      uuid: nil,
      model_usage: nil,
      permission_denials: nil,
      structured_output: nil,
      errors: nil
    }

    struct!(Message.Result, Map.merge(defaults, attrs))
  end

  def text_content(text) do
    %Content.Text{type: "text", text: text}
  end

  def tool_use_content(name, input, id \\ nil) do
    %Content.ToolUse{
      type: "tool_use",
      id: id || "tool_#{:rand.uniform(1000)}",
      name: name,
      input: input
    }
  end

  def tool_result_content(content, tool_use_id \\ nil, is_error \\ false) do
    %Content.ToolResult{
      type: :tool_result,
      tool_use_id: tool_use_id || "tool_#{:rand.uniform(1000)}",
      content: content,
      is_error: is_error
    }
  end

  def thinking_content(thinking, signature \\ nil) do
    %Content.Thinking{
      type: :thinking,
      thinking: thinking,
      signature: signature || "sig_#{:rand.uniform(10_000)}"
    }
  end

  @doc """
  Creates an assistant message containing a tool use block.
  """
  def assistant_message_with_tool_use(opts \\ []) do
    tool_id = Keyword.get(opts, :tool_id, "tool_#{:rand.uniform(10_000)}")
    tool_name = Keyword.get(opts, :tool_name, "Read")
    tool_input = Keyword.get(opts, :tool_input, %{"path" => "/tmp/test.txt"})
    text = Keyword.get(opts, :text)

    content =
      if text do
        [text_content(text), tool_use_content(tool_name, tool_input, tool_id)]
      else
        [tool_use_content(tool_name, tool_input, tool_id)]
      end

    assistant_message(
      message: %{
        id: Keyword.get(opts, :message_id, "msg_#{:rand.uniform(10_000)}"),
        content: content,
        stop_reason: :tool_use
      }
    )
  end

  @doc """
  Creates a user message containing a tool result block.
  """
  def user_message_with_tool_result(opts \\ []) do
    tool_use_id = Keyword.get(opts, :tool_use_id, "tool_#{:rand.uniform(10_000)}")
    content = Keyword.get(opts, :content, "file contents here")
    is_error = Keyword.get(opts, :is_error, false)

    user_message(
      message: %{
        id: Keyword.get(opts, :message_id, "msg_#{:rand.uniform(10_000)}"),
        content: [tool_result_content(content, tool_use_id, is_error)]
      }
    )
  end

  @doc """
  Creates an assistant message containing a thinking block.
  """
  def assistant_message_with_thinking(opts \\ []) do
    thinking_text = Keyword.get(opts, :thinking, "I'm reasoning through this...")
    signature = Keyword.get(opts, :signature, "sig_test")
    text = Keyword.get(opts, :text)

    content =
      if text do
        [thinking_content(thinking_text, signature), text_content(text)]
      else
        [thinking_content(thinking_text, signature)]
      end

    assistant_message(
      message: %{
        id: Keyword.get(opts, :message_id, "msg_#{:rand.uniform(10_000)}"),
        content: content
      }
    )
  end

  # Stream event fixtures for partial message streaming

  @doc """
  Creates a message_start stream event.
  """
  def stream_event_message_start(attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{
        type: :message_start,
        message: Map.get(attrs, :message, %{})
      },
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates a content_block_start stream event.
  """
  def stream_event_content_block_start(attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{
        type: :content_block_start,
        index: Map.get(attrs, :index, 0),
        content_block: Map.get(attrs, :content_block, %{type: :text, text: ""})
      },
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates a text delta stream event.
  """
  def stream_event_text_delta(text, attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{
        type: :content_block_delta,
        index: Map.get(attrs, :index, 0),
        delta: %{type: :text_delta, text: text}
      },
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates an input_json_delta stream event for tool use streaming.
  """
  def stream_event_input_json_delta(partial_json, attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{
        type: :content_block_delta,
        index: Map.get(attrs, :index, 0),
        delta: %{type: :input_json_delta, partial_json: partial_json}
      },
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates a thinking_delta stream event for extended thinking streaming.
  """
  def stream_event_thinking_delta(thinking, attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{
        type: :content_block_delta,
        index: Map.get(attrs, :index, 0),
        delta: %{type: :thinking_delta, thinking: thinking}
      },
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates a content_block_stop stream event.
  """
  def stream_event_content_block_stop(attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{
        type: :content_block_stop,
        index: Map.get(attrs, :index, 0)
      },
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates a message_delta stream event.
  """
  def stream_event_message_delta(attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{
        type: :message_delta,
        delta: Map.get(attrs, :delta, %{stop_reason: "end_turn"}),
        usage: Map.get(attrs, :usage, %{})
      },
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates a message_stop stream event.
  """
  def stream_event_message_stop(attrs \\ %{}) do
    defaults = %{
      type: :stream_event,
      event: %{type: :message_stop},
      session_id: Map.get(attrs, :session_id, "test-123"),
      parent_tool_use_id: Map.get(attrs, :parent_tool_use_id),
      uuid: Map.get(attrs, :uuid, "uuid-#{:rand.uniform(1000)}")
    }

    struct!(StreamEvent, defaults)
  end

  @doc """
  Creates a complete sequence of stream events simulating a text response.
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
end
