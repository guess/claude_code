defmodule ClaudeCode.Message.SystemMessage.PluginInstallTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Message.SystemMessage.PluginInstall

  describe "new/1" do
    test "parses a valid plugin_install message with all fields" do
      json = %{
        "type" => "system",
        "subtype" => "plugin_install",
        "status" => "installed",
        "name" => "my-plugin",
        "uuid" => "uuid-123",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = PluginInstall.new(json)
      assert message.type == :system
      assert message.subtype == :plugin_install
      assert message.status == :installed
      assert message.name == "my-plugin"
      assert message.error == nil
      assert message.uuid == "uuid-123"
      assert message.session_id == "session-abc"
    end

    test "parses status 'started' to :started" do
      assert {:ok, message} = PluginInstall.new(base_json("started"))
      assert message.status == :started
    end

    test "parses status 'installed' to :installed" do
      assert {:ok, message} = PluginInstall.new(base_json("installed"))
      assert message.status == :installed
    end

    test "parses status 'failed' to :failed" do
      assert {:ok, message} = PluginInstall.new(base_json("failed"))
      assert message.status == :failed
    end

    test "parses status 'completed' to :completed" do
      assert {:ok, message} = PluginInstall.new(base_json("completed"))
      assert message.status == :completed
    end

    test "parses unknown status to nil" do
      assert {:ok, message} = PluginInstall.new(base_json("pending"))
      assert message.status == nil
    end

    test "handles error field for failed installation" do
      json = %{
        "type" => "system",
        "subtype" => "plugin_install",
        "status" => "failed",
        "error" => "Plugin not found in registry",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = PluginInstall.new(json)
      assert message.status == :failed
      assert message.error == "Plugin not found in registry"
    end

    test "handles optional fields when absent" do
      json = %{
        "type" => "system",
        "subtype" => "plugin_install",
        "session_id" => "session-abc"
      }

      assert {:ok, message} = PluginInstall.new(json)
      assert message.status == nil
      assert message.name == nil
      assert message.error == nil
      assert message.uuid == nil
    end

    test "returns error for missing required fields (session_id)" do
      json = %{"type" => "system", "subtype" => "plugin_install"}
      assert {:error, :missing_required_fields} = PluginInstall.new(json)
    end

    test "returns error for invalid message type" do
      json = %{"type" => "assistant"}
      assert {:error, :invalid_message_type} = PluginInstall.new(json)
    end
  end

  describe "plugin_install?/1" do
    test "returns true for a PluginInstall struct" do
      message = %PluginInstall{
        type: :system,
        subtype: :plugin_install,
        session_id: "session-1"
      }

      assert PluginInstall.plugin_install?(message) == true
    end

    test "returns false for other values" do
      assert PluginInstall.plugin_install?(%{}) == false
      assert PluginInstall.plugin_install?(nil) == false
      assert PluginInstall.plugin_install?("string") == false
    end
  end

  defp base_json(status) do
    %{
      "type" => "system",
      "subtype" => "plugin_install",
      "status" => status,
      "session_id" => "session-abc"
    }
  end
end
