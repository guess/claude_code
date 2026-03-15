defmodule ClaudeCode.History.ConversationChainTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.History.ConversationChain
  alias ClaudeCode.History.SessionMessage

  @moduletag :history

  describe "parse_entries/1" do
    test "parses valid JSONL entries" do
      content = """
      {"type":"user","uuid":"u1","message":{"content":"Hello"}}
      {"type":"assistant","uuid":"a1","message":{"content":"Hi"}}
      """

      entries = ConversationChain.parse_entries(content)
      assert length(entries) == 2
      assert Enum.at(entries, 0)["uuid"] == "u1"
      assert Enum.at(entries, 1)["uuid"] == "a1"
    end

    test "skips non-transcript entry types" do
      content = """
      {"type":"summary","summary":"test"}
      {"type":"user","uuid":"u1","message":{"content":"Hello"}}
      {"type":"queue-operation","operation":"enqueue"}
      {"type":"file-history-snapshot","snapshot":{}}
      """

      entries = ConversationChain.parse_entries(content)
      assert length(entries) == 1
    end

    test "skips entries without uuid" do
      content = """
      {"type":"user","message":{"content":"Hello"}}
      {"type":"user","uuid":"u1","message":{"content":"World"}}
      """

      entries = ConversationChain.parse_entries(content)
      assert length(entries) == 1
      assert hd(entries)["uuid"] == "u1"
    end

    test "skips invalid JSON lines" do
      content = """
      not valid json
      {"type":"user","uuid":"u1","message":{"content":"Hello"}}
      """

      entries = ConversationChain.parse_entries(content)
      assert length(entries) == 1
    end
  end

  describe "build/1" do
    test "builds linear chain" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "parentUuid" => nil, "message" => %{"content" => "A"}},
        %{"type" => "assistant", "uuid" => "a1", "parentUuid" => "u1", "message" => %{"content" => "B"}},
        %{"type" => "user", "uuid" => "u2", "parentUuid" => "a1", "message" => %{"content" => "C"}}
      ]

      chain = ConversationChain.build(entries)
      assert length(chain) == 3
      assert Enum.at(chain, 0)["uuid"] == "u1"
      assert Enum.at(chain, 1)["uuid"] == "a1"
      assert Enum.at(chain, 2)["uuid"] == "u2"
    end

    test "handles branched conversation - picks latest branch" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "parentUuid" => nil, "message" => %{"content" => "Root"}},
        %{"type" => "assistant", "uuid" => "a1", "parentUuid" => "u1", "message" => %{"content" => "Branch A"}},
        %{"type" => "assistant", "uuid" => "a2", "parentUuid" => "u1", "message" => %{"content" => "Branch B"}}
      ]

      chain = ConversationChain.build(entries)
      # Should pick the latest branch (a2, highest file position)
      assert length(chain) == 2
      assert Enum.at(chain, 0)["uuid"] == "u1"
      assert Enum.at(chain, 1)["uuid"] == "a2"
    end

    test "filters sidechain leaves" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "parentUuid" => nil, "message" => %{"content" => "Main"}},
        %{"type" => "assistant", "uuid" => "a1", "parentUuid" => "u1", "message" => %{"content" => "Main reply"}},
        %{
          "type" => "assistant",
          "uuid" => "a2",
          "parentUuid" => "u1",
          "isSidechain" => true,
          "message" => %{"content" => "Sidechain"}
        }
      ]

      chain = ConversationChain.build(entries)
      # Should pick a1 (non-sidechain) even though a2 has higher position
      assert length(chain) == 2
      assert Enum.at(chain, 1)["uuid"] == "a1"
    end

    test "handles empty entries" do
      assert ConversationChain.build([]) == []
    end

    test "handles single entry" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "message" => %{"content" => "Solo"}}
      ]

      chain = ConversationChain.build(entries)
      assert length(chain) == 1
      assert hd(chain)["uuid"] == "u1"
    end

    test "handles compaction boundary" do
      entries = [
        %{
          "type" => "user",
          "uuid" => "u1",
          "parentUuid" => nil,
          "isCompactSummary" => true,
          "message" => %{"content" => "Summary"}
        },
        %{"type" => "assistant", "uuid" => "a1", "parentUuid" => "u1", "message" => %{"content" => "Response"}},
        %{"type" => "user", "uuid" => "u2", "parentUuid" => "a1", "message" => %{"content" => "Follow-up"}}
      ]

      chain = ConversationChain.build(entries)
      assert length(chain) == 3
      # isCompactSummary messages are included in the chain
    end

    test "skips team messages in leaf selection" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "parentUuid" => nil, "message" => %{"content" => "Main"}},
        %{"type" => "assistant", "uuid" => "a1", "parentUuid" => "u1", "message" => %{"content" => "Main reply"}},
        %{
          "type" => "assistant",
          "uuid" => "a2",
          "parentUuid" => "u1",
          "teamName" => "team-1",
          "message" => %{"content" => "Team msg"}
        }
      ]

      chain = ConversationChain.build(entries)
      assert Enum.at(chain, 1)["uuid"] == "a1"
    end

    test "prevents infinite loops from circular parentUuid" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "parentUuid" => "u2", "message" => %{"content" => "A"}},
        %{"type" => "user", "uuid" => "u2", "parentUuid" => "u1", "message" => %{"content" => "B"}}
      ]

      # Should not hang — cycle detection prevents infinite loop
      chain = ConversationChain.build(entries)
      assert is_list(chain)
    end
  end

  describe "filter_visible/1" do
    test "keeps user and assistant messages" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "message" => %{"content" => "Hello"}},
        %{"type" => "assistant", "uuid" => "a1", "message" => %{"content" => "Hi"}},
        %{"type" => "system", "uuid" => "s1"},
        %{"type" => "progress", "uuid" => "p1"}
      ]

      visible = ConversationChain.filter_visible(entries)
      assert length(visible) == 2
    end

    test "excludes isMeta messages" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "isMeta" => true, "message" => %{"content" => "meta"}},
        %{"type" => "user", "uuid" => "u2", "message" => %{"content" => "real"}}
      ]

      visible = ConversationChain.filter_visible(entries)
      assert length(visible) == 1
      assert hd(visible)["uuid"] == "u2"
    end

    test "excludes sidechain messages" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "isSidechain" => true, "message" => %{"content" => "side"}},
        %{"type" => "user", "uuid" => "u2", "message" => %{"content" => "main"}}
      ]

      visible = ConversationChain.filter_visible(entries)
      assert length(visible) == 1
      assert hd(visible)["uuid"] == "u2"
    end

    test "excludes team messages" do
      entries = [
        %{"type" => "user", "uuid" => "u1", "teamName" => "team-1", "message" => %{"content" => "team"}},
        %{"type" => "user", "uuid" => "u2", "message" => %{"content" => "main"}}
      ]

      visible = ConversationChain.filter_visible(entries)
      assert length(visible) == 1
      assert hd(visible)["uuid"] == "u2"
    end

    test "includes isCompactSummary messages" do
      entries = [
        %{
          "type" => "user",
          "uuid" => "u1",
          "isCompactSummary" => true,
          "message" => %{"content" => "Summary of earlier conversation"}
        }
      ]

      visible = ConversationChain.filter_visible(entries)
      assert length(visible) == 1
    end
  end

  describe "to_session_message/1" do
    test "converts user entry with parsed content" do
      entry = %{
        "type" => "user",
        "uuid" => "u1",
        "sessionId" => "session-123",
        "message" => %{"role" => "user", "content" => "Hello"}
      }

      msg = ConversationChain.to_session_message(entry)
      assert %SessionMessage{} = msg
      assert msg.type == :user
      assert msg.uuid == "u1"
      assert msg.session_id == "session-123"
      assert msg.message == %{content: "Hello", role: :user}
      assert is_nil(msg.parent_tool_use_id)
    end

    test "converts assistant entry with parsed text blocks" do
      entry = %{
        "type" => "assistant",
        "uuid" => "a1",
        "sessionId" => "session-123",
        "message" => %{"content" => [%{"type" => "text", "text" => "Hi"}]}
      }

      msg = ConversationChain.to_session_message(entry)
      assert %SessionMessage{} = msg
      assert msg.type == :assistant
      assert msg.uuid == "a1"
      assert [%ClaudeCode.Content.TextBlock{text: "Hi"}] = msg.message.content
    end

    test "converts user entry with tool_result content blocks" do
      entry = %{
        "type" => "user",
        "uuid" => "u1",
        "sessionId" => "session-123",
        "message" => %{
          "role" => "user",
          "content" => [
            %{"type" => "tool_result", "tool_use_id" => "t1", "content" => "done"}
          ]
        }
      }

      msg = ConversationChain.to_session_message(entry)
      assert msg.type == :user
      assert [%ClaudeCode.Content.ToolResultBlock{tool_use_id: "t1"}] = msg.message.content
    end
  end
end
