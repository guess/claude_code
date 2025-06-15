defmodule ClaudeCode.Message.SystemTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.System

  describe "new/1" do
    test "parses a valid system init message" do
      json = %{
        "type" => "system",
        "subtype" => "init",
        "cwd" => "/Users/test/project",
        "session_id" => "abc-123",
        "tools" => ["Read", "Write", "LS"],
        "mcp_servers" => [
          %{"name" => "memory", "status" => "connected"},
          %{"name" => "filesystem", "status" => "connected"}
        ],
        "model" => "claude-opus-4",
        "permissionMode" => "default",
        "apiKeySource" => "ANTHROPIC_API_KEY"
      }

      assert {:ok, message} = System.new(json)
      assert message.type == :system
      assert message.subtype == :init
      assert message.cwd == "/Users/test/project"
      assert message.session_id == "abc-123"
      assert message.tools == ["Read", "Write", "LS"]
      assert length(message.mcp_servers) == 2
      assert hd(message.mcp_servers) == %{name: "memory", status: "connected"}
      assert message.model == "claude-opus-4"
      assert message.permission_mode == :default
      assert message.api_key_source == "ANTHROPIC_API_KEY"
    end

    test "parses bypassPermissions mode correctly" do
      json = %{
        "type" => "system",
        "subtype" => "init",
        "cwd" => "/test",
        "session_id" => "xyz",
        "tools" => [],
        "mcp_servers" => [],
        "model" => "claude",
        "permissionMode" => "bypassPermissions",
        "apiKeySource" => "env"
      }

      assert {:ok, message} = System.new(json)
      assert message.permission_mode == :bypass_permissions
    end

    test "returns error for invalid type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = System.new(json)
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "init"}
      assert {:error, {:missing_fields, _}} = System.new(json)
    end
  end

  describe "type guards" do
    test "system_message?/1 returns true for system messages" do
      {:ok, message} = System.new(valid_system_json())
      assert System.system_message?(message)
    end

    test "system_message?/1 returns false for non-system messages" do
      refute System.system_message?(%{type: :assistant})
      refute System.system_message?(nil)
      refute System.system_message?("not a message")
    end
  end

  describe "from fixture" do
    test "parses real CLI system message" do
      # Load from our captured fixture
      fixture_path = "test/fixtures/cli_messages/simple_hello.json"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # First line should be system message
      {:ok, json} = Jason.decode(hd(lines))

      assert json["type"] == "system"
      assert {:ok, message} = System.new(json)
      assert message.type == :system
      assert message.subtype == :init
      assert is_binary(message.session_id)
      assert is_list(message.tools)
      assert is_list(message.mcp_servers)
    end
  end

  defp valid_system_json do
    %{
      "type" => "system",
      "subtype" => "init",
      "cwd" => "/test",
      "session_id" => "test-123",
      "tools" => [],
      "mcp_servers" => [],
      "model" => "claude",
      "permissionMode" => "default",
      "apiKeySource" => "env"
    }
  end
end
