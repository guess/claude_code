defmodule ClaudeCode.Message.SystemMessage.ApiRetryTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.ApiRetry

  describe "new/1" do
    test "parses a valid api_retry message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "api_retry",
        "attempt" => 2,
        "max_retries" => 3,
        "retry_delay_ms" => 1000,
        "error_status" => 429,
        "error" => %{
          "type" => "error",
          "error" => %{"type" => "rate_limit_error", "message" => "Rate limit exceeded"}
        },
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ApiRetry.new(json)
      assert message.type == :system
      assert message.subtype == :api_retry
      assert message.attempt == 2
      assert message.max_retries == 3
      assert message.retry_delay_ms == 1000
      assert message.error_status == 429

      assert message.error == %{
               "type" => "error",
               "error" => %{"type" => "rate_limit_error", "message" => "Rate limit exceeded"}
             }

      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "handles nil error_status" do
      json = %{
        "type" => "system",
        "subtype" => "api_retry",
        "attempt" => 1,
        "max_retries" => 3,
        "retry_delay_ms" => 500,
        "error_status" => nil,
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ApiRetry.new(json)
      assert message.error_status == nil
    end

    test "handles optional fields when absent" do
      json = %{
        "type" => "system",
        "subtype" => "api_retry",
        "attempt" => 1,
        "max_retries" => 3,
        "retry_delay_ms" => 500,
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ApiRetry.new(json)
      assert message.error_status == nil
      assert message.error == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "api_retry"}
      assert {:error, :missing_required_fields} = ApiRetry.new(json)
    end

    test "returns error for missing attempt" do
      json = %{
        "type" => "system",
        "subtype" => "api_retry",
        "max_retries" => 3,
        "retry_delay_ms" => 500,
        "session_id" => "session-abc"
      }

      assert {:error, :missing_required_fields} = ApiRetry.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = ApiRetry.new(json)
    end
  end

  describe "api_retry?/1" do
    test "returns true for an ApiRetry struct" do
      message = %ApiRetry{
        type: :system,
        subtype: :api_retry,
        attempt: 1,
        max_retries: 3,
        retry_delay_ms: 500,
        session_id: "session-1"
      }

      assert ApiRetry.api_retry?(message) == true
    end

    test "returns false for other values" do
      assert ApiRetry.api_retry?(%{}) == false
      assert ApiRetry.api_retry?(nil) == false
      assert ApiRetry.api_retry?("string") == false
    end
  end
end
