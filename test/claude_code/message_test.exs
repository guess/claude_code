defmodule ClaudeCode.MessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message
  alias ClaudeCode.Message.AuthStatusMessage
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.ToolProgressMessage
  alias ClaudeCode.Message.ToolUseSummaryMessage

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

    test "message?/1 returns true for rate limit events" do
      {:ok, msg} =
        RateLimitEvent.new(%{
          "type" => "rate_limit_event",
          "rate_limit_info" => %{"status" => "allowed"},
          "session_id" => "1"
        })

      assert Message.message?(msg)
    end

    test "message?/1 returns true for tool progress messages" do
      {:ok, msg} =
        ToolProgressMessage.new(%{
          "type" => "tool_progress",
          "tool_use_id" => "t1",
          "tool_name" => "Bash",
          "session_id" => "1"
        })

      assert Message.message?(msg)
    end

    test "message?/1 returns true for tool use summary messages" do
      {:ok, msg} =
        ToolUseSummaryMessage.new(%{
          "type" => "tool_use_summary",
          "summary" => "Read files",
          "session_id" => "1"
        })

      assert Message.message?(msg)
    end

    test "message?/1 returns true for auth status messages" do
      {:ok, msg} =
        AuthStatusMessage.new(%{
          "type" => "auth_status",
          "isAuthenticating" => true,
          "session_id" => "1"
        })

      assert Message.message?(msg)
    end

    test "message?/1 returns true for prompt suggestion messages" do
      {:ok, msg} =
        PromptSuggestionMessage.new(%{
          "type" => "prompt_suggestion",
          "suggestion" => "Next step",
          "session_id" => "1"
        })

      assert Message.message?(msg)
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

    test "message_type/1 returns correct types for new message types" do
      {:ok, rl} =
        RateLimitEvent.new(%{
          "type" => "rate_limit_event",
          "rate_limit_info" => %{"status" => "allowed"},
          "session_id" => "1"
        })

      assert Message.message_type(rl) == :rate_limit_event

      {:ok, tp} =
        ToolProgressMessage.new(%{
          "type" => "tool_progress",
          "tool_use_id" => "t1",
          "tool_name" => "Bash",
          "session_id" => "1"
        })

      assert Message.message_type(tp) == :tool_progress

      {:ok, tus} =
        ToolUseSummaryMessage.new(%{
          "type" => "tool_use_summary",
          "summary" => "Read files",
          "session_id" => "1"
        })

      assert Message.message_type(tus) == :tool_use_summary

      {:ok, auth} =
        AuthStatusMessage.new(%{
          "type" => "auth_status",
          "isAuthenticating" => false,
          "session_id" => "1"
        })

      assert Message.message_type(auth) == :auth_status

      {:ok, ps} =
        PromptSuggestionMessage.new(%{
          "type" => "prompt_suggestion",
          "suggestion" => "Next step",
          "session_id" => "1"
        })

      assert Message.message_type(ps) == :prompt_suggestion
    end
  end
end
