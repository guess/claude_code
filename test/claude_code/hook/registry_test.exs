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

  describe "new/1" do
    test "builds registry from hooks map" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash]}
        ]
      }

      {registry, _wire} = Registry.new(hooks)
      assert map_size(registry.callbacks) == 1
    end

    test "builds registry with nil hooks" do
      {registry, wire} = Registry.new(nil)
      assert registry.callbacks == %{}
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

      {registry, _wire} = Registry.new(hooks)
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

      {registry, _wire} = Registry.new(hooks)
      assert map_size(registry.callbacks) == 1
    end

    test "tracks execution target for each callback ID" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash], where: :remote},
          %{hooks: [AllowAll]}
        ]
      }

      {registry, _wire} = Registry.new(hooks)
      assert Registry.target(registry, "hook_0") == :remote
      assert Registry.target(registry, "hook_1") == :local
    end

    test "defaults :where to :local when not specified" do
      hooks = %{
        PreToolUse: [%{hooks: [DenyBash]}]
      }

      {registry, _wire} = Registry.new(hooks)
      assert Registry.target(registry, "hook_0") == :local
    end

    test "wire format includes callbacks from all execution targets" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash], where: :remote},
          %{hooks: [AllowAll], where: :local}
        ]
      }

      {_registry, wire} = Registry.new(hooks)
      assert %{"PreToolUse" => entries} = wire
      assert length(entries) == 2

      [remote_entry, local_entry] = entries
      assert remote_entry["hookCallbackIds"] == ["hook_0"]
      assert local_entry["hookCallbackIds"] == ["hook_1"]
    end

    test "split/1 partitions registry by execution target" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash], where: :remote},
          %{hooks: [AllowAll]}
        ],
        PostToolUse: [
          %{hooks: [AuditLogger], where: :remote}
        ]
      }

      {registry, _wire} = Registry.new(hooks)
      {local_reg, remote_reg} = Registry.split(registry)

      # Local gets AllowAll (the only :local hook)
      local_callbacks = Map.values(local_reg.callbacks)
      assert local_callbacks == [AllowAll]

      # Remote gets DenyBash + AuditLogger
      remote_callbacks = remote_reg.callbacks |> Map.values() |> MapSet.new()
      assert remote_callbacks == MapSet.new([DenyBash, AuditLogger])
    end
  end

  describe "to_wire_format/1 (via new/1)" do
    test "produces correct wire format for hooks" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash], timeout: 30}
        ]
      }

      {_registry, wire} = Registry.new(hooks)

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

      {_registry, wire} = Registry.new(hooks)

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

      {_registry, wire} = Registry.new(hooks)

      assert %{"PreToolUse" => [matcher_entry]} = wire
      assert matcher_entry["hookCallbackIds"] == ["hook_0", "hook_1"]
    end

    test "returns nil wire format when no hooks configured" do
      {_registry, wire} = Registry.new(nil)
      assert wire == nil
    end

    test "returns nil wire format for empty hooks map" do
      {_registry, wire} = Registry.new(%{})
      assert wire == nil
    end
  end

  describe "lookup/2" do
    test "finds callback by ID" do
      hooks = %{
        PreToolUse: [%{hooks: [DenyBash]}]
      }

      {registry, _wire} = Registry.new(hooks)
      assert {:ok, DenyBash} = Registry.lookup(registry, "hook_0")
    end

    test "returns error for unknown ID" do
      {registry, _wire} = Registry.new(%{})
      assert :error = Registry.lookup(registry, "hook_999")
    end
  end
end
