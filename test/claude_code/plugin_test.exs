defmodule ClaudeCode.PluginTest do
  use ExUnit.Case

  import Mox

  alias ClaudeCode.Plugin
  alias ClaudeCode.System.Mock

  setup :verify_on_exit!

  # Point cli_path at a real executable so the resolver's File.exists? check
  # passes. The System.cmd mock intercepts the actual command execution.
  @cli_path System.find_executable("true")

  setup do
    Application.put_env(:claude_code, ClaudeCode.System, Mock)
    Application.put_env(:claude_code, :cli_path, @cli_path)

    on_exit(fn ->
      Application.delete_env(:claude_code, ClaudeCode.System)
      Application.put_env(:claude_code, :cli_path, "/nonexistent/test/claude")
    end)
  end

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
    end

    test "fields default to nil" do
      plugin = %Plugin{}
      assert plugin.id == nil
      assert plugin.enabled == nil
    end
  end

  describe "list/1" do
    test "parses JSON output into plugin structs" do
      json =
        Jason.encode!([
          %{
            "id" => "code-simplifier@claude-plugins-official",
            "version" => "1.0.0",
            "scope" => "project",
            "enabled" => true,
            "installPath" => "/Users/test/.claude/plugins/cache/code-simplifier/1.0.0",
            "installedAt" => "2026-02-01T09:39:39.165Z",
            "lastUpdated" => "2026-02-01T09:39:39.165Z",
            "projectPath" => "/Users/test/my-project"
          },
          %{
            "id" => "github@claude-plugins-official",
            "version" => "b36fd4b75301",
            "scope" => "user",
            "enabled" => true,
            "installPath" => "/Users/test/.claude/plugins/cache/github/b36fd4b75301",
            "installedAt" => "2026-02-27T18:07:13.111Z",
            "lastUpdated" => "2026-03-12T00:38:36.193Z",
            "mcpServers" => %{"github" => %{"type" => "http", "url" => "https://example.com"}}
          }
        ])

      expect(Mock, :cmd, fn _binary, ["plugin", "list", "--json"], _opts -> {json, 0} end)
      assert {:ok, [plugin1, plugin2]} = Plugin.list()

      assert %Plugin{
               id: "code-simplifier@claude-plugins-official",
               version: "1.0.0",
               scope: :project,
               enabled: true,
               project_path: "/Users/test/my-project",
               mcp_servers: nil
             } = plugin1

      assert %Plugin{
               id: "github@claude-plugins-official",
               scope: :user,
               mcp_servers: %{"github" => %{"type" => "http", "url" => "https://example.com"}}
             } = plugin2
    end

    test "returns empty list for empty JSON array" do
      expect(Mock, :cmd, fn _binary, ["plugin", "list", "--json"], _opts -> {"[]", 0} end)
      assert {:ok, []} = Plugin.list()
    end

    test "returns error on non-zero exit" do
      expect(Mock, :cmd, fn _binary, _args, _opts ->
        {"Error: something went wrong", 1}
      end)

      assert {:error, "Error: something went wrong"} = Plugin.list()
    end

    test "returns error on invalid JSON" do
      expect(Mock, :cmd, fn _binary, _args, _opts -> {"not valid json", 0} end)

      assert {:error, "Failed to parse plugin list JSON: not valid json"} =
               Plugin.list()
    end
  end

  describe "install/2" do
    test "passes plugin ID and scope to CLI" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "install", "--scope", "project", "my-plugin@my-org"]

        {"Installing plugin \"my-plugin@my-org\"...\n✔ Successfully installed plugin: my-plugin@my-org (scope: project)\n",
         0}
      end)

      assert {:ok, output} = Plugin.install("my-plugin@my-org", scope: :project)
      assert output =~ "Successfully installed"
    end

    test "omits scope when not provided" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "install", "my-plugin@my-org"]
        {"✔ Successfully installed\n", 0}
      end)

      assert {:ok, _} = Plugin.install("my-plugin@my-org")
    end
  end

  describe "enable/2" do
    test "enables a plugin" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "enable", "my-plugin@org"]
        {"✔ Successfully enabled plugin: my-plugin (scope: user)\n", 0}
      end)

      assert {:ok, output} = Plugin.enable("my-plugin@org")
      assert output =~ "Successfully enabled"
    end

    test "returns error when already enabled" do
      expect(Mock, :cmd, fn _binary, _args, _opts ->
        {~s(Failed to enable plugin "my-plugin@org": Plugin "my-plugin@org" is already enabled\n), 1}
      end)

      assert {:error, msg} = Plugin.enable("my-plugin@org")
      assert msg =~ "already enabled"
    end
  end

  describe "disable/2" do
    test "disables a plugin" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "disable", "my-plugin@org"]
        {"✔ Successfully disabled plugin: my-plugin (scope: user)\n", 0}
      end)

      assert {:ok, _} = Plugin.disable("my-plugin@org")
    end
  end

  describe "disable_all/1" do
    test "passes --all flag" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "disable", "--all", "--scope", "project"]
        {"✔ Disabled all plugins\n", 0}
      end)

      assert {:ok, _} = Plugin.disable_all(scope: :project)
    end
  end

  describe "uninstall/2" do
    test "uninstalls a plugin" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "uninstall", "my-plugin@org"]
        {"✔ Successfully uninstalled\n", 0}
      end)

      assert {:ok, _} = Plugin.uninstall("my-plugin@org")
    end
  end

  describe "update/2" do
    test "updates a plugin" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "update", "--scope", "user", "my-plugin@org"]
        {"✔ Successfully updated\n", 0}
      end)

      assert {:ok, _} = Plugin.update("my-plugin@org", scope: :user)
    end
  end
end
