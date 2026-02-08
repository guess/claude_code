defmodule ClaudeCode.Message.SystemMessageTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage

  describe "new/1" do
    test "parses a valid system init message" do
      json = %{
        "type" => "system",
        "subtype" => "init",
        "uuid" => "550e8400-e29b-41d4-a716-446655440000",
        "cwd" => "/Users/test/project",
        "session_id" => "abc-123",
        "tools" => ["Read", "Write", "LS"],
        "mcp_servers" => [
          %{"name" => "memory", "status" => "connected"},
          %{"name" => "filesystem", "status" => "connected"}
        ],
        "model" => "claude-opus-4",
        "permissionMode" => "default",
        "apiKeySource" => "ANTHROPIC_API_KEY",
        "slash_commands" => ["/help", "/clear", "/search"],
        "output_style" => "default",
        "claude_code_version" => "2.1.7",
        "agents" => ["Bash", "Explore"],
        "skills" => [],
        "plugins" => []
      }

      assert {:ok, message} = SystemMessage.new(json)
      assert message.type == :system
      assert message.subtype == :init
      assert message.uuid == "550e8400-e29b-41d4-a716-446655440000"
      assert message.cwd == "/Users/test/project"
      assert message.session_id == "abc-123"
      assert message.tools == ["Read", "Write", "LS"]
      assert length(message.mcp_servers) == 2
      assert hd(message.mcp_servers) == %{name: "memory", status: "connected"}
      assert message.model == "claude-opus-4"
      assert message.permission_mode == :default
      assert message.api_key_source == "ANTHROPIC_API_KEY"
      assert message.slash_commands == ["/help", "/clear", "/search"]
      assert message.output_style == "default"
      assert message.claude_code_version == "2.1.7"
      assert message.agents == ["Bash", "Explore"]
      assert message.skills == []
      assert message.plugins == []
    end

    test "parses bypassPermissions mode correctly" do
      json = %{
        "type" => "system",
        "subtype" => "init",
        "uuid" => "550e8400-e29b-41d4-a716-446655440000",
        "cwd" => "/test",
        "session_id" => "xyz",
        "tools" => [],
        "mcp_servers" => [],
        "model" => "claude",
        "permissionMode" => "bypassPermissions",
        "apiKeySource" => "env",
        "slash_commands" => [],
        "output_style" => "default"
      }

      assert {:ok, message} = SystemMessage.new(json)
      assert message.permission_mode == :bypass_permissions
    end

    test "returns error for invalid type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = SystemMessage.new(json)
    end

    test "returns error for missing required fields" do
      json = %{"type" => "system", "subtype" => "init"}
      assert {:error, {:missing_fields, _}} = SystemMessage.new(json)
    end
  end

  describe "type guards" do
    test "system_message?/1 returns true for system messages" do
      {:ok, message} = SystemMessage.new(valid_system_json())
      assert SystemMessage.system_message?(message)
    end

    test "system_message?/1 returns false for non-system messages" do
      refute SystemMessage.system_message?(%{type: :assistant})
      refute SystemMessage.system_message?(nil)
      refute SystemMessage.system_message?("not a message")
    end
  end

  describe "from fixture" do
    test "parses real CLI system message" do
      # Load from our captured fixture
      fixture_path = "test/fixtures/cli_messages/simple_hello.jsonl"
      lines = fixture_path |> File.read!() |> String.split("\n", trim: true)

      # First line should be system message
      {:ok, json} = Jason.decode(hd(lines))

      assert json["type"] == "system"
      assert {:ok, message} = SystemMessage.new(json)
      assert message.type == :system
      assert message.subtype == :init
      assert is_binary(message.session_id)
      assert is_list(message.tools)
      assert is_list(message.mcp_servers)
    end
  end

  describe "plugins parsing" do
    test "parses plugins as objects with name and path" do
      json =
        Map.put(valid_system_json(), "plugins", [
          %{"name" => "my-plugin", "path" => "/path/to/plugin"},
          %{"name" => "other", "path" => "/path/to/other"}
        ])

      assert {:ok, message} = SystemMessage.new(json)
      assert length(message.plugins) == 2
      assert hd(message.plugins) == %{name: "my-plugin", path: "/path/to/plugin"}
    end

    test "parses plugins as strings for backwards compatibility" do
      json = Map.put(valid_system_json(), "plugins", ["plugin-a", "plugin-b"])

      assert {:ok, message} = SystemMessage.new(json)
      assert message.plugins == ["plugin-a", "plugin-b"]
    end

    test "handles mixed plugin formats" do
      json = Map.put(valid_system_json(), "plugins", [%{"name" => "obj-plugin", "path" => "/path"}, "string-plugin"])

      assert {:ok, message} = SystemMessage.new(json)
      assert length(message.plugins) == 2
      assert Enum.at(message.plugins, 0) == %{name: "obj-plugin", path: "/path"}
      assert Enum.at(message.plugins, 1) == "string-plugin"
    end

    test "handles nil plugins" do
      json = Map.delete(valid_system_json(), "plugins")

      assert {:ok, message} = SystemMessage.new(json)
      assert message.plugins == []
    end
  end

  defp valid_system_json do
    %{
      "type" => "system",
      "subtype" => "init",
      "uuid" => "550e8400-e29b-41d4-a716-446655440000",
      "cwd" => "/test",
      "session_id" => "test-123",
      "tools" => [],
      "mcp_servers" => [],
      "model" => "claude",
      "permissionMode" => "default",
      "apiKeySource" => "env",
      "slash_commands" => ["/help", "/clear"],
      "output_style" => "default"
    }
  end
end
