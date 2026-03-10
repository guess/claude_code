defmodule ClaudeCode.Message.RateLimitEventTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.RateLimitEvent

  describe "new/1" do
    test "parses a valid rate limit event with all fields" do
      json = %{
        "type" => "rate_limit_event",
        "rate_limit_info" => %{
          "status" => "allowed_warning",
          "resets_at" => 1_700_000_000_000,
          "utilization" => 0.85,
          "rate_limit_type" => "five_hour",
          "overage_status" => "allowed",
          "overage_resets_at" => 1_700_001_000_000,
          "overage_disabled_reason" => nil,
          "is_using_overage" => false,
          "surpassed_threshold" => 0.8
        },
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = RateLimitEvent.new(json)
      assert message.type == :rate_limit_event
      assert message.rate_limit_info.status == :allowed_warning
      assert message.rate_limit_info.resets_at == 1_700_000_000_000
      assert message.rate_limit_info.utilization == 0.85
      assert message.rate_limit_info.rate_limit_type == "five_hour"
      assert message.rate_limit_info.overage_status == "allowed"
      assert message.rate_limit_info.overage_resets_at == 1_700_001_000_000
      assert message.rate_limit_info.overage_disabled_reason == nil
      assert message.rate_limit_info.is_using_overage == false
      assert message.rate_limit_info.surpassed_threshold == 0.8
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses rate limit event with minimal info" do
      json = %{
        "type" => "rate_limit_event",
        "rate_limit_info" => %{"status" => "allowed"},
        "session_id" => "session-abc"
      }

      assert {:ok, message} = RateLimitEvent.new(json)
      assert message.rate_limit_info.status == :allowed
      assert message.rate_limit_info.resets_at == nil
      assert message.rate_limit_info.utilization == nil
      assert message.rate_limit_info.rate_limit_type == nil
      assert message.rate_limit_info.overage_status == nil
      assert message.rate_limit_info.overage_resets_at == nil
      assert message.rate_limit_info.is_using_overage == nil
      assert message.rate_limit_info.surpassed_threshold == nil
      assert message.uuid == nil
    end

    test "parses rejected rate limit event" do
      json = %{
        "type" => "rate_limit_event",
        "rate_limit_info" => %{
          "status" => "rejected",
          "resets_at" => 1_700_000_060_000
        },
        "uuid" => "uuid-456",
        "session_id" => "session-def"
      }

      assert {:ok, message} = RateLimitEvent.new(json)
      assert message.rate_limit_info.status == :rejected
      assert message.rate_limit_info.resets_at == 1_700_000_060_000
    end

    test "returns error for missing required fields" do
      json = %{"type" => "rate_limit_event"}
      assert {:error, :missing_required_fields} = RateLimitEvent.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = RateLimitEvent.new(json)
    end
  end
end
