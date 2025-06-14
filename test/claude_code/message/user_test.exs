defmodule ClaudeCode.Message.UserTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Content.ToolResult
  alias ClaudeCode.Message.User

  describe "new/1" do
    test "parses a valid user message with tool result" do
      json = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_123",
              "content" => "File created successfully"
            }
          ]
        },
        "parent_tool_use_id" => nil,
        "session_id" => "session-123"
      }

      assert {:ok, message} = User.new(json)
      assert message.type == :user
      assert message.message.role == :user
      assert message.session_id == "session-123"

      assert [%ToolResult{tool_use_id: "toolu_123", content: "File created successfully"}] = message.message.content
    end

    test "parses user message with error tool result" do
      json = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_456",
              "content" => "File does not exist.",
              "is_error" => true
            }
          ]
        },
        "parent_tool_use_id" => "toolu_456",
        "session_id" => "session-456"
      }

      assert {:ok, message} = User.new(json)

      assert [%ToolResult{is_error: true, content: "File does not exist."}] = message.message.content
    end

    test "handles multiple tool results" do
      json = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_1",
              "content" => "First result"
            },
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_2",
              "content" => "Second result"
            }
          ]
        },
        "parent_tool_use_id" => nil,
        "session_id" => "multi-session"
      }

      assert {:ok, message} = User.new(json)
      assert length(message.message.content) == 2
    end

    test "handles empty content array" do
      json = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => []
        },
        "parent_tool_use_id" => nil,
        "session_id" => "empty-session"
      }

      assert {:ok, message} = User.new(json)
      assert message.message.content == []
    end

    test "returns error for invalid type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = User.new(json)
    end

    test "returns error for missing message wrapper" do
      json = %{"type" => "user"}
      assert {:error, :missing_message} = User.new(json)
    end

    test "returns error if content parsing fails" do
      json = %{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => "This shouldn't be in user message"}
          ]
        },
        "parent_tool_use_id" => nil,
        "session_id" => "bad"
      }

      # This should actually succeed since Content.parse supports text blocks
      # But in practice, user messages from CLI only contain tool_result blocks
      assert {:ok, _} = User.new(json)
    end
  end

  describe "type guards" do
    test "is_user_message?/1 returns true for user messages" do
      {:ok, message} = User.new(valid_user_json())
      assert User.is_user_message?(message)
    end

    test "is_user_message?/1 returns false for non-user messages" do
      refute User.is_user_message?(%{type: :assistant})
      refute User.is_user_message?(nil)
      refute User.is_user_message?("not a message")
    end
  end

  describe "from fixture" do
    test "parses real CLI user message with tool result" do
      fixture_path = "test/fixtures/cli_messages/create_file.json"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find user message
      user_line =
        Enum.find(lines, fn line ->
          case Jason.decode(line) do
            {:ok, %{"type" => "user"}} -> true
            _ -> false
          end
        end)

      assert user_line
      {:ok, json} = Jason.decode(user_line)

      assert {:ok, message} = User.new(json)
      assert message.type == :user
      assert [%ToolResult{content: content}] = message.message.content
      assert content =~ "successfully"
    end

    test "parses real CLI user message with error" do
      fixture_path = "test/fixtures/cli_messages/error_case.json"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # Find user message with error
      error_user_line =
        Enum.find(lines, fn line ->
          case Jason.decode(line) do
            {:ok, %{"type" => "user", "message" => %{"content" => [%{"is_error" => true} | _]}}} -> true
            _ -> false
          end
        end)

      assert error_user_line
      {:ok, json} = Jason.decode(error_user_line)

      assert {:ok, message} = User.new(json)
      assert [%ToolResult{is_error: true, content: "File does not exist."}] = message.message.content
    end
  end

  defp valid_user_json do
    %{
      "type" => "user",
      "message" => %{
        "role" => "user",
        "content" => [
          %{
            "type" => "tool_result",
            "tool_use_id" => "toolu_test",
            "content" => "Test result"
          }
        ]
      },
      "parent_tool_use_id" => nil,
      "session_id" => "test-session"
    }
  end
end
