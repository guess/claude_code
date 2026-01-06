defmodule ClaudeCode.Message.CompactBoundaryMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.CompactBoundaryMessage

  describe "new/1" do
    test "parses a valid compact boundary message with manual trigger" do
      json = %{
        "type" => "system",
        "subtype" => "compact_boundary",
        "uuid" => "550e8400-e29b-41d4-a716-446655440000",
        "session_id" => "abc-123",
        "compact_metadata" => %{
          "trigger" => "manual",
          "pre_tokens" => 8000
        }
      }

      assert {:ok, message} = CompactBoundaryMessage.new(json)
      assert message.type == :system
      assert message.subtype == :compact_boundary
      assert message.uuid == "550e8400-e29b-41d4-a716-446655440000"
      assert message.session_id == "abc-123"
      assert message.compact_metadata.trigger == "manual"
      assert message.compact_metadata.pre_tokens == 8000
    end

    test "parses a valid compact boundary message with auto trigger" do
      json = %{
        "type" => "system",
        "subtype" => "compact_boundary",
        "uuid" => "abc-def-ghi",
        "session_id" => "session-456",
        "compact_metadata" => %{
          "trigger" => "auto",
          "pre_tokens" => 5000
        }
      }

      assert {:ok, message} = CompactBoundaryMessage.new(json)
      assert message.compact_metadata.trigger == "auto"
      assert message.compact_metadata.pre_tokens == 5000
    end

    test "defaults pre_tokens to 0 when missing" do
      json = %{
        "type" => "system",
        "subtype" => "compact_boundary",
        "uuid" => "uuid-123",
        "session_id" => "session-789",
        "compact_metadata" => %{"trigger" => "manual"}
      }

      assert {:ok, message} = CompactBoundaryMessage.new(json)
      assert message.compact_metadata.pre_tokens == 0
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant", "subtype" => "compact_boundary"}
      assert {:error, :invalid_message_type} = CompactBoundaryMessage.new(json)
    end

    test "returns error for wrong subtype" do
      json = %{
        "type" => "system",
        "subtype" => "init",
        "uuid" => "uuid-123",
        "session_id" => "session-123",
        "tools" => []
      }

      assert {:error, :invalid_message_type} = CompactBoundaryMessage.new(json)
    end

    test "returns error for missing uuid" do
      json = %{
        "type" => "system",
        "subtype" => "compact_boundary",
        "session_id" => "session-123",
        "compact_metadata" => %{"trigger" => "auto", "pre_tokens" => 5000}
      }

      assert {:error, {:missing_fields, missing}} = CompactBoundaryMessage.new(json)
      assert :uuid in missing
    end

    test "returns error for missing session_id" do
      json = %{
        "type" => "system",
        "subtype" => "compact_boundary",
        "uuid" => "uuid-123",
        "compact_metadata" => %{"trigger" => "auto", "pre_tokens" => 5000}
      }

      assert {:error, {:missing_fields, missing}} = CompactBoundaryMessage.new(json)
      assert :session_id in missing
    end

    test "returns error for missing compact_metadata" do
      json = %{
        "type" => "system",
        "subtype" => "compact_boundary",
        "uuid" => "uuid-123",
        "session_id" => "session-123"
      }

      assert {:error, {:missing_fields, missing}} = CompactBoundaryMessage.new(json)
      assert :compact_metadata in missing
    end

    test "returns error for multiple missing required fields" do
      json = %{
        "type" => "system",
        "subtype" => "compact_boundary"
      }

      assert {:error, {:missing_fields, missing}} = CompactBoundaryMessage.new(json)
      assert :uuid in missing
      assert :session_id in missing
      assert :compact_metadata in missing
    end
  end

  describe "type guards" do
    test "compact_boundary_message?/1 returns true for compact boundary messages" do
      {:ok, message} = CompactBoundaryMessage.new(valid_compact_boundary_json())
      assert CompactBoundaryMessage.compact_boundary_message?(message)
    end

    test "compact_boundary_message?/1 returns false for non-compact-boundary messages" do
      refute CompactBoundaryMessage.compact_boundary_message?(%{type: :system, subtype: :init})
      refute CompactBoundaryMessage.compact_boundary_message?(%{type: :assistant})
      refute CompactBoundaryMessage.compact_boundary_message?(nil)
      refute CompactBoundaryMessage.compact_boundary_message?("not a message")
      refute CompactBoundaryMessage.compact_boundary_message?(%{})
    end
  end

  describe "from fixture" do
    test "parses compact boundary message from fixture helper" do
      message = compact_boundary_fixture()
      assert message.type == :system
      assert message.subtype == :compact_boundary
      assert is_binary(message.uuid)
      assert is_binary(message.session_id)
      assert is_map(message.compact_metadata)
    end

    test "parses compact boundary message from fixture with custom attrs" do
      message =
        compact_boundary_fixture(%{
          compact_metadata: %{trigger: "auto", pre_tokens: 10_000}
        })

      assert message.compact_metadata.trigger == "auto"
      assert message.compact_metadata.pre_tokens == 10_000
    end
  end

  defp valid_compact_boundary_json do
    %{
      "type" => "system",
      "subtype" => "compact_boundary",
      "uuid" => "550e8400-e29b-41d4-a716-446655440000",
      "session_id" => "test-123",
      "compact_metadata" => %{
        "trigger" => "auto",
        "pre_tokens" => 5000
      }
    }
  end

  defp compact_boundary_fixture(attrs \\ %{}) do
    defaults = %{
      type: :system,
      subtype: :compact_boundary,
      uuid: "550e8400-e29b-41d4-a716-446655440000",
      session_id: "test-123",
      compact_metadata: %{trigger: "manual", pre_tokens: 1000}
    }

    struct!(CompactBoundaryMessage, Map.merge(defaults, attrs))
  end
end
