defmodule ClaudeCode.Plugin.MarketplaceTest do
  use ExUnit.Case

  alias ClaudeCode.Plugin.Marketplace

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
      assert marketplace.install_location =~ "claude-plugins-official"
    end

    test "fields default to nil" do
      marketplace = %Marketplace{}
      assert marketplace.name == nil
      assert marketplace.source == nil
      assert marketplace.repo == nil
      assert marketplace.install_location == nil
    end
  end

  describe "list/1" do
    @tag :integration
    test "returns list of marketplace structs" do
      assert {:ok, marketplaces} = Marketplace.list()
      assert is_list(marketplaces)

      if marketplaces != [] do
        marketplace = hd(marketplaces)
        assert %Marketplace{} = marketplace
        assert is_binary(marketplace.name)
        assert is_binary(marketplace.source)
      end
    end
  end

  describe "add/2, remove/1 lifecycle" do
    @tag :integration
    @tag :destructive
    test "adds and removes a marketplace" do
      # This test modifies user settings — only run when explicitly opted in
      source = "anthropics/claude-code"

      assert {:ok, _output} = Marketplace.add(source)
      assert {:ok, marketplaces} = Marketplace.list()
      assert Enum.any?(marketplaces, &(&1.repo == source))

      # Find the name assigned to clean up
      marketplace = Enum.find(marketplaces, &(&1.repo == source))
      assert {:ok, _output} = Marketplace.remove(marketplace.name)
    end
  end

  describe "update/1" do
    @tag :integration
    test "updates all marketplaces" do
      assert {:ok, _output} = Marketplace.update()
    end
  end
end
