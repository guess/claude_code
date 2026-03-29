defmodule ClaudeCode.Message.SystemMessage.ApiRetryTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.ApiRetry

  describe "new/1" do
    test "parses a valid api_retry message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "api_retry",
        "attempt" => 1,
        "max_retries" => 3,
        "retry_delay_ms" => 5000,
        "error_status" => 429,
        "error" => "rate_limit",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ApiRetry.new(json)
      assert message.type == :system
      assert message.subtype == :api_retry
      assert message.attempt == 1
      assert message.max_retries == 3
      assert message.retry_delay_ms == 5000
      assert message.error_status == 429
      assert message.error == :rate_limit
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses with null error_status (connection error)" do
      json = %{
        "type" => "system",
        "subtype" => "api_retry",
        "attempt" => 2,
        "max_retries" => 3,
        "retry_delay_ms" => 10_000,
        "error_status" => nil,
        "error" => "server_error",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ApiRetry.new(json)
      assert message.error_status == nil
      assert message.error == :server_error
    end

    test "parses with missing error_status key (connection error)" do
      json = %{
        "type" => "system",
        "subtype" => "api_retry",
        "attempt" => 1,
        "max_retries" => 3,
        "retry_delay_ms" => 5000,
        "error" => "unknown",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = ApiRetry.new(json)
      assert message.error_status == nil
      assert message.error == :unknown
    end

    test "parses all valid error types" do
      error_types = [
        "authentication_failed",
        "billing_error",
        "rate_limit",
        "invalid_request",
        "server_error",
        "unknown",
        "max_output_tokens"
      ]

      for error_type <- error_types do
        json = base_json(error_type)
        assert {:ok, message} = ApiRetry.new(json)
        assert message.error == String.to_atom(error_type)
      end
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "api_retry"}
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
        retry_delay_ms: 5000,
        error: :rate_limit,
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

  defp base_json(error) do
    %{
      "type" => "system",
      "subtype" => "api_retry",
      "attempt" => 1,
      "max_retries" => 3,
      "retry_delay_ms" => 5000,
      "error_status" => 429,
      "error" => error,
      "session_id" => "session-abc"
    }
  end
end
