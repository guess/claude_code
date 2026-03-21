defmodule ClaudeCode.Plugin.MarketplaceTest do
  use ClaudeCode.Case

  alias ClaudeCode.Plugin.Marketplace
  alias ClaudeCode.System.Mock

  @moduletag :mock_system

  setup :verify_on_exit!

  describe "struct" do
    test "has expected fields" do
      marketplace = %Marketplace{
        name: "claude-plugins-official",
        source: "github",
        repo: "anthropics/claude-plugins-official",
        install_location: "/Users/test/.claude/plugins/marketplaces/claude-plugins-official"
      }

      assert marketplace.name == "claude-plugins-official"
      assert marketplace.source == "github"
      assert marketplace.repo == "anthropics/claude-plugins-official"
    end

    test "fields default to nil" do
      marketplace = %Marketplace{}
      assert marketplace.name == nil
      assert marketplace.source == nil
    end
  end

  describe "list/1" do
    test "parses JSON output into marketplace structs" do
      json =
        Jason.encode!([
          %{
            "name" => "claude-plugins-official",
            "source" => "github",
            "repo" => "anthropics/claude-plugins-official",
            "installLocation" => "/Users/test/.claude/plugins/marketplaces/claude-plugins-official"
          },
          %{
            "name" => "expo-plugins",
            "source" => "github",
            "repo" => "expo/skills",
            "installLocation" => "/Users/test/.claude/plugins/marketplaces/expo-plugins"
          }
        ])

      expect(Mock, :cmd, fn _binary, ["plugin", "marketplace", "list", "--json"], _opts ->
        {json, 0}
      end)

      assert {:ok, [m1, m2]} = Marketplace.list()

      assert %Marketplace{
               name: "claude-plugins-official",
               source: "github",
               repo: "anthropics/claude-plugins-official"
             } = m1

      assert %Marketplace{name: "expo-plugins", repo: "expo/skills"} = m2
    end

    test "returns empty list for empty JSON array" do
      expect(Mock, :cmd, fn _binary, _args, _opts -> {"[]", 0} end)
      assert {:ok, []} = Marketplace.list()
    end

    test "returns error on non-zero exit" do
      expect(Mock, :cmd, fn _binary, _args, _opts -> {"Error: failed", 1} end)
      assert {:error, "Error: failed"} = Marketplace.list()
    end

    test "returns error on invalid JSON" do
      expect(Mock, :cmd, fn _binary, _args, _opts -> {"not json", 0} end)
      assert {:error, msg} = Marketplace.list()
      assert msg =~ "Failed to parse marketplace list JSON"
    end

    test "passes node: option through to System.cmd" do
      expect(Mock, :cmd, fn _binary, ["plugin", "marketplace", "list", "--json"], opts ->
        assert Keyword.get(opts, :node) == :"test@node"
        {"[]", 0}
      end)

      assert {:ok, []} = Marketplace.list(node: :"test@node")
    end
  end

  describe "add/2" do
    test "passes source and scope to CLI" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "marketplace", "add", "--scope", "project", "owner/repo"]
        {"✔ Added marketplace\n", 0}
      end)

      assert {:ok, _} = Marketplace.add("owner/repo", scope: :project)
    end

    test "passes sparse checkout paths" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == [
                 "plugin",
                 "marketplace",
                 "add",
                 "--sparse",
                 ".claude-plugin",
                 "plugins",
                 "owner/monorepo"
               ]

        {"✔ Added marketplace\n", 0}
      end)

      assert {:ok, _} =
               Marketplace.add("owner/monorepo",
                 sparse: [".claude-plugin", "plugins"]
               )
    end

    test "omits scope and sparse when not provided" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "marketplace", "add", "owner/repo"]
        {"✔ Added\n", 0}
      end)

      assert {:ok, _} = Marketplace.add("owner/repo")
    end
  end

  describe "remove/2" do
    test "removes a marketplace by name" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "marketplace", "remove", "my-marketplace"]
        {"✔ Removed marketplace\n", 0}
      end)

      assert {:ok, _} = Marketplace.remove("my-marketplace")
    end

    test "returns error when marketplace not found" do
      expect(Mock, :cmd, fn _binary, _args, _opts ->
        {"Error: Marketplace not found\n", 1}
      end)

      assert {:error, "Error: Marketplace not found"} = Marketplace.remove("nonexistent")
    end

    test "passes node: through to System.cmd" do
      expect(Mock, :cmd, fn _binary, ["plugin", "marketplace", "remove", "my-marketplace"], opts ->
        assert Keyword.get(opts, :node) == :"test@node"
        {"Removed", 0}
      end)

      assert {:ok, "Removed"} = Marketplace.remove("my-marketplace", node: :"test@node")
    end
  end

  describe "update/2" do
    test "updates all marketplaces when nil name given" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "marketplace", "update"]
        {"✔ Updated all\n", 0}
      end)

      assert {:ok, _} = Marketplace.update(nil)
    end

    test "updates a specific marketplace" do
      expect(Mock, :cmd, fn _binary, args, _opts ->
        assert args == ["plugin", "marketplace", "update", "my-marketplace"]
        {"✔ Updated\n", 0}
      end)

      assert {:ok, _} = Marketplace.update("my-marketplace")
    end

    test "passes node: through to System.cmd" do
      expect(Mock, :cmd, fn _binary, ["plugin", "marketplace", "update", "my-marketplace"], opts ->
        assert Keyword.get(opts, :node) == :"test@node"
        {"Updated", 0}
      end)

      assert {:ok, "Updated"} = Marketplace.update("my-marketplace", node: :"test@node")
    end
  end
end
