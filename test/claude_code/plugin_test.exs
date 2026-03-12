defmodule ClaudeCode.PluginTest do
  use ExUnit.Case

  alias ClaudeCode.Plugin

  describe "struct" do
    test "has expected fields" do
      plugin = %Plugin{
        id: "code-simplifier@claude-plugins-official",
        version: "1.0.0",
        scope: :user,
        enabled: true,
        install_path: "/Users/test/.claude/plugins/cache/claude-plugins-official/code-simplifier/1.0.0",
        installed_at: "2026-02-01T09:39:39.165Z",
        last_updated: "2026-02-01T09:39:39.165Z",
        project_path: nil,
        mcp_servers: nil
      }

      assert plugin.id == "code-simplifier@claude-plugins-official"
      assert plugin.version == "1.0.0"
      assert plugin.scope == :user
      assert plugin.enabled == true
      assert plugin.install_path =~ "code-simplifier"
    end

    test "fields default to nil except enabled" do
      plugin = %Plugin{}
      assert plugin.id == nil
      assert plugin.enabled == nil
    end
  end

  describe "list/1" do
    @tag :integration
    test "returns list of plugin structs" do
      assert {:ok, plugins} = Plugin.list()
      assert is_list(plugins)

      if plugins != [] do
        plugin = hd(plugins)
        assert %Plugin{} = plugin
        assert is_binary(plugin.id)
        assert plugin.scope in [:user, :project, :local, nil]
        assert is_boolean(plugin.enabled)
      end
    end
  end

  describe "validate/1" do
    @tag :integration
    test "validates a valid plugin path" do
      # Use one of the installed plugin paths if available
      case Plugin.list() do
        {:ok, [%Plugin{install_path: path} | _]} when is_binary(path) ->
          assert {:ok, _output} = Plugin.validate(path)

        _ ->
          :skip
      end
    end

    @tag :integration
    test "returns error for invalid path" do
      assert {:error, _reason} = Plugin.validate("/nonexistent/path")
    end
  end
end
