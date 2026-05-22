defmodule ClaudeCode.Message.SystemMessage.MemoryRecallTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.MemoryRecall

  describe "new/1" do
    test "parses a valid memory_recall message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "memory_recall",
        "mode" => "select",
        "memories" => [
          %{"path" => "/path/to/memory.md", "scope" => "personal", "body" => "Memory content here"},
          %{"path" => "/team/notes.md", "scope" => "team"}
        ],
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = MemoryRecall.new(json)
      assert message.type == :system
      assert message.subtype == :memory_recall
      assert message.mode == :select
      assert length(message.memories) == 2
      assert hd(message.memories).path == "/path/to/memory.md"
      assert hd(message.memories).scope == :personal
      assert hd(message.memories).body == "Memory content here"
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses mode 'select' to :select" do
      assert {:ok, message} = MemoryRecall.new(base_json("select"))
      assert message.mode == :select
    end

    test "parses mode 'synthesize' to :synthesize" do
      assert {:ok, message} = MemoryRecall.new(base_json("synthesize"))
      assert message.mode == :synthesize
    end

    test "parses unknown mode to nil" do
      assert {:ok, message} = MemoryRecall.new(base_json("unknown"))
      assert message.mode == nil
    end

    test "parses memory scope 'personal' to :personal" do
      json = base_json_with_scope("personal")
      assert {:ok, message} = MemoryRecall.new(json)
      assert hd(message.memories).scope == :personal
    end

    test "parses memory scope 'team' to :team" do
      json = base_json_with_scope("team")
      assert {:ok, message} = MemoryRecall.new(json)
      assert hd(message.memories).scope == :team
    end

    test "parses memory scope 'organization' to :organization" do
      json = base_json_with_scope("organization")
      assert {:ok, message} = MemoryRecall.new(json)
      assert hd(message.memories).scope == :organization
    end

    test "parses unknown scope to nil" do
      json = base_json_with_scope("workspace")
      assert {:ok, message} = MemoryRecall.new(json)
      assert hd(message.memories).scope == nil
    end

    test "handles memory without body" do
      json = %{
        "type" => "system",
        "subtype" => "memory_recall",
        "mode" => "select",
        "memories" => [%{"path" => "/path/mem.md", "scope" => "personal"}],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = MemoryRecall.new(json)
      assert hd(message.memories).body == nil
    end

    test "handles empty memories list" do
      json = %{
        "type" => "system",
        "subtype" => "memory_recall",
        "mode" => "synthesize",
        "memories" => [],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = MemoryRecall.new(json)
      assert message.memories == []
    end

    test "handles absent uuid" do
      json = %{
        "type" => "system",
        "subtype" => "memory_recall",
        "mode" => "select",
        "memories" => [],
        "session_id" => "session-abc"
      }

      assert {:ok, message} = MemoryRecall.new(json)
      assert message.uuid == nil
    end

    test "returns error for missing required fields (memories)" do
      json = %{"type" => "system", "subtype" => "memory_recall"}
      assert {:error, :missing_required_fields} = MemoryRecall.new(json)
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "system",
        "subtype" => "memory_recall",
        "memories" => []
      }

      assert {:error, :missing_required_fields} = MemoryRecall.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = MemoryRecall.new(json)
    end
  end

  describe "memory_recall?/1" do
    test "returns true for a MemoryRecall struct" do
      message = %MemoryRecall{
        type: :system,
        subtype: :memory_recall,
        memories: [],
        session_id: "session-1"
      }

      assert MemoryRecall.memory_recall?(message) == true
    end

    test "returns false for other values" do
      assert MemoryRecall.memory_recall?(%{}) == false
      assert MemoryRecall.memory_recall?(nil) == false
      assert MemoryRecall.memory_recall?("string") == false
    end
  end

  defp base_json(mode) do
    %{
      "type" => "system",
      "subtype" => "memory_recall",
      "mode" => mode,
      "memories" => [],
      "session_id" => "session-abc"
    }
  end

  defp base_json_with_scope(scope) do
    %{
      "type" => "system",
      "subtype" => "memory_recall",
      "mode" => "select",
      "memories" => [%{"path" => "/path/mem.md", "scope" => scope}],
      "session_id" => "session-abc"
    }
  end
end
