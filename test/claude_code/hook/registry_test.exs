defmodule ClaudeCode.Hook.RegistryTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Hook.Registry

  defmodule AllowAll do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  defmodule DenyBash do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(%{tool_name: "Bash"}, _id), do: {:deny, "No bash"}
    def call(_input, _id), do: :allow
  end

  defmodule AuditLogger do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :ok
  end

  describe "new/2" do
    test "builds registry from hooks map" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash]}
        ]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert map_size(registry.callbacks) == 1
    end

    test "builds registry with can_use_tool callback" do
      {registry, _wire} = Registry.new(%{}, AllowAll)
      assert registry.can_use_tool == AllowAll
    end

    test "builds registry with nil hooks and nil can_use_tool" do
      {registry, wire} = Registry.new(nil, nil)
      assert registry.callbacks == %{}
      assert registry.can_use_tool == nil
      assert wire == nil
    end

    test "assigns sequential callback IDs" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash]},
          %{hooks: [AllowAll]}
        ],
        PostToolUse: [
          %{hooks: [AuditLogger]}
        ]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert map_size(registry.callbacks) == 3
      assert Map.has_key?(registry.callbacks, "hook_0")
      assert Map.has_key?(registry.callbacks, "hook_1")
      assert Map.has_key?(registry.callbacks, "hook_2")
    end

    test "supports anonymous function callbacks" do
      hook_fn = fn _input, _id -> :ok end

      hooks = %{
        PostToolUse: [
          %{hooks: [hook_fn]}
        ]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert map_size(registry.callbacks) == 1
    end
  end

  describe "to_wire_format/1 (via new/2)" do
    test "produces correct wire format for hooks" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash], timeout: 30}
        ]
      }

      {_registry, wire} = Registry.new(hooks, nil)

      assert %{"PreToolUse" => [matcher_entry]} = wire
      assert matcher_entry["matcher"] == "Bash"
      assert matcher_entry["hookCallbackIds"] == ["hook_0"]
      assert matcher_entry["timeout"] == 30
    end

    test "nil matcher is passed as null" do
      hooks = %{
        PostToolUse: [
          %{hooks: [AuditLogger]}
        ]
      }

      {_registry, wire} = Registry.new(hooks, nil)

      assert %{"PostToolUse" => [matcher_entry]} = wire
      assert matcher_entry["matcher"] == nil
      assert matcher_entry["hookCallbackIds"] == ["hook_0"]
      refute Map.has_key?(matcher_entry, "timeout")
    end

    test "multiple callbacks per matcher produce multiple IDs" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash, AllowAll]}
        ]
      }

      {_registry, wire} = Registry.new(hooks, nil)

      assert %{"PreToolUse" => [matcher_entry]} = wire
      assert matcher_entry["hookCallbackIds"] == ["hook_0", "hook_1"]
    end

    test "returns nil wire format when no hooks configured" do
      {_registry, wire} = Registry.new(nil, AllowAll)
      assert wire == nil
    end

    test "returns nil wire format for empty hooks map" do
      {_registry, wire} = Registry.new(%{}, nil)
      assert wire == nil
    end
  end

  describe "lookup/2" do
    test "finds callback by ID" do
      hooks = %{
        PreToolUse: [%{hooks: [DenyBash]}]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert {:ok, DenyBash} = Registry.lookup(registry, "hook_0")
    end

    test "returns error for unknown ID" do
      {registry, _wire} = Registry.new(%{}, nil)
      assert :error = Registry.lookup(registry, "hook_999")
    end
  end
end
