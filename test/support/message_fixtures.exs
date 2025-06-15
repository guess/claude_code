defmodule ClaudeCode.Test.MessageFixtures do
  @moduledoc """
  Test fixtures for creating properly structured messages.
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Message

  def system_message(attrs \\ %{}) do
    defaults = %{
      type: "system",
      subtype: "init",
      model: "claude-3",
      session_id: "test-123",
      cwd: "/test",
      tools: [],
      mcp_servers: [],
      permission_mode: "auto",
      api_key_source: "ANTHROPIC_API_KEY"
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
      usage: %{}
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
end
