defmodule ClaudeCode.Message.ResultMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.ResultMessage

  describe "new/1" do
    test "parses a successful result message" do
      json = %{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "duration_ms" => 1500,
        "duration_api_ms" => 1200,
        "num_turns" => 3,
        "result" => "Task completed successfully!",
        "session_id" => "session-123",
        "total_cost_usd" => 0.0125,
        "usage" => %{
          "input_tokens" => 500,
          "cache_creation_input_tokens" => 100,
          "cache_read_input_tokens" => 200,
          "output_tokens" => 150,
          "server_tool_use" => %{
            "web_search_requests" => 0
          }
        }
      }

      assert {:ok, message} = ResultMessage.new(json)
      assert message.type == :result
      assert message.subtype == :success
      assert message.is_error == false
      assert message.duration_ms == 1500
      assert message.duration_api_ms == 1200
      assert message.num_turns == 3
      assert message.result == "Task completed successfully!"
      assert message.session_id == "session-123"
      assert message.total_cost_usd == 0.0125

      assert message.usage.input_tokens == 500
      assert message.usage.output_tokens == 150
      assert message.usage.server_tool_use.web_search_requests == 0
    end

    test "parses an error result message" do
      json = %{
        "type" => "result",
        "subtype" => "error",
        "is_error" => true,
        "duration_ms" => 500,
        "duration_api_ms" => 0,
        "num_turns" => 1,
        "result" => "Error: API key invalid",
        "session_id" => "error-session",
        "total_cost_usd" => 0.0,
        "usage" => %{
          "input_tokens" => 0,
          "cache_creation_input_tokens" => 0,
          "cache_read_input_tokens" => 0,
          "output_tokens" => 0,
          "server_tool_use" => %{
            "web_search_requests" => 0
          }
        }
      }

      assert {:ok, message} = ResultMessage.new(json)
      assert message.subtype == :error
      assert message.is_error == true
      assert message.result =~ "Error"
      assert message.total_cost_usd == 0.0
    end

    test "parses subtype as atom" do
      base_json = fn subtype ->
        %{
          "type" => "result",
          "subtype" => subtype,
          "is_error" => false,
          "duration_ms" => 100,
          "duration_api_ms" => 90,
          "num_turns" => 1,
          "result" => "OK",
          "session_id" => "test",
          "total_cost_usd" => 0.001,
          "usage" => %{
            "input_tokens" => 10,
            "cache_creation_input_tokens" => 0,
            "cache_read_input_tokens" => 0,
            "output_tokens" => 5,
            "server_tool_use" => %{"web_search_requests" => 0}
          }
        }
      end

      {:ok, msg1} = ResultMessage.new(base_json.("success"))
      assert msg1.subtype == :success

      {:ok, msg2} = ResultMessage.new(base_json.("error"))
      assert msg2.subtype == :error
    end

    test "handles missing server_tool_use in usage" do
      json = %{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "duration_ms" => 100,
        "duration_api_ms" => 90,
        "num_turns" => 1,
        "result" => "OK",
        "session_id" => "test",
        "total_cost_usd" => 0.001,
        "usage" => %{
          "input_tokens" => 10,
          "cache_creation_input_tokens" => 0,
          "cache_read_input_tokens" => 0,
          "output_tokens" => 5
        }
      }

      assert {:ok, message} = ResultMessage.new(json)
      assert message.usage.server_tool_use.web_search_requests == 0
    end

    test "returns error for invalid type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = ResultMessage.new(json)
    end

    test "returns error for missing required fields" do
      json = %{"type" => "result", "subtype" => "success"}
      assert {:error, {:missing_fields, _}} = ResultMessage.new(json)
    end
  end

  describe "type guards" do
    test "result_message?/1 returns true for result messages" do
      {:ok, message} = ResultMessage.new(valid_result_json())
      assert ResultMessage.result_message?(message)
    end

    test "result_message?/1 returns false for non-result messages" do
      refute ResultMessage.result_message?(%{type: :assistant})
      refute ResultMessage.result_message?(nil)
      refute ResultMessage.result_message?("not a message")
    end
  end

  describe "from fixture" do
    test "parses real CLI result message" do
      fixture_path = "test/fixtures/cli_messages/simple_hello.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Last line should be result message
      {:ok, json} = Jason.decode(List.last(lines))

      assert json["type"] == "result"
      assert {:ok, message} = ResultMessage.new(json)
      assert message.type == :result
      assert message.subtype == :success
      assert message.is_error == false
      assert is_float(message.total_cost_usd)
      assert is_binary(message.result)
      assert is_integer(message.num_turns)
    end

    test "parses result message with high token usage" do
      fixture_path = "test/fixtures/cli_messages/read_file.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find result message
      result_line =
        Enum.find(lines, fn line ->
          case Jason.decode(line) do
            {:ok, %{"type" => "result"}} -> true
            _ -> false
          end
        end)

      assert result_line
      {:ok, json} = Jason.decode(result_line)

      assert {:ok, message} = ResultMessage.new(json)
      assert message.usage.input_tokens > 0
      assert message.usage.output_tokens > 0
      assert message.total_cost_usd > 0
    end
  end

  defp valid_result_json do
    %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "duration_ms" => 1000,
      "duration_api_ms" => 900,
      "num_turns" => 1,
      "result" => "Test completed",
      "session_id" => "test-session",
      "total_cost_usd" => 0.01,
      "usage" => %{
        "input_tokens" => 100,
        "cache_creation_input_tokens" => 0,
        "cache_read_input_tokens" => 50,
        "output_tokens" => 25,
        "server_tool_use" => %{
          "web_search_requests" => 0
        }
      }
    }
  end
end
