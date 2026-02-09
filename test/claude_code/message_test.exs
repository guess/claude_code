defmodule ClaudeCode.MessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.SystemMessage

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
end
