defmodule ClaudeCode.SandboxTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Sandbox
  alias ClaudeCode.Sandbox.Filesystem
  alias ClaudeCode.Sandbox.Network

  describe "new/1" do
    test "creates sandbox with all scalar fields" do
      sandbox =
        Sandbox.new(
          enabled: true,
          auto_allow_bash_if_sandboxed: true,
          allow_unsandboxed_commands: false,
          enable_weaker_nested_sandbox: true,
          excluded_commands: ["docker", "nix"],
          ignore_violations: %{"filesystem" => ["write_denied"]},
          ripgrep: %{command: "/usr/bin/rg", args: ["--no-ignore"]}
        )

      assert %Sandbox{
               enabled: true,
               auto_allow_bash_if_sandboxed: true,
               allow_unsandboxed_commands: false,
               enable_weaker_nested_sandbox: true,
               excluded_commands: ["docker", "nix"],
               ignore_violations: %{"filesystem" => ["write_denied"]},
               ripgrep: %{command: "/usr/bin/rg", args: ["--no-ignore"]},
               filesystem: nil,
               network: nil
             } = sandbox
    end

    test "creates sandbox with no fields (all nil)" do
      sandbox = Sandbox.new([])

      assert %Sandbox{
               enabled: nil,
               auto_allow_bash_if_sandboxed: nil,
               allow_unsandboxed_commands: nil,
               enable_weaker_nested_sandbox: nil,
               excluded_commands: nil,
               ignore_violations: nil,
               ripgrep: nil,
               filesystem: nil,
               network: nil
             } = sandbox
    end

    test "auto-wraps filesystem keyword list into struct" do
      sandbox = Sandbox.new(filesystem: [allow_write: ["/tmp"], deny_read: ["~/.aws"]])

      assert %Filesystem{allow_write: ["/tmp"], deny_read: ["~/.aws"]} = sandbox.filesystem
    end

    test "auto-wraps filesystem map into struct" do
      sandbox = Sandbox.new(filesystem: %{allow_write: ["/tmp"], deny_write: ["/etc"]})

      assert %Filesystem{allow_write: ["/tmp"], deny_write: ["/etc"]} = sandbox.filesystem
    end

    test "passes through filesystem struct unchanged" do
      fs = Filesystem.new(allow_write: ["/tmp"])
      sandbox = Sandbox.new(filesystem: fs)

      assert sandbox.filesystem === fs
    end

    test "auto-wraps network keyword list into struct" do
      sandbox = Sandbox.new(network: [allowed_domains: ["*.example.com"], http_proxy_port: 8080])

      assert %Network{allowed_domains: ["*.example.com"], http_proxy_port: 8080} =
               sandbox.network
    end

    test "auto-wraps network map into struct" do
      sandbox =
        Sandbox.new(network: %{allowed_domains: ["example.com"], allow_local_binding: true})

      assert %Network{allowed_domains: ["example.com"], allow_local_binding: true} =
               sandbox.network
    end

    test "passes through network struct unchanged" do
      net = Network.new(allowed_domains: ["example.com"])
      sandbox = Sandbox.new(network: net)

      assert sandbox.network === net
    end

    test "creates sandbox from atom-keyed map" do
      sandbox = Sandbox.new(%{enabled: true, excluded_commands: ["docker"]})

      assert sandbox.enabled == true
      assert sandbox.excluded_commands == ["docker"]
      assert sandbox.auto_allow_bash_if_sandboxed == nil
    end

    test "creates sandbox from string-keyed map" do
      sandbox =
        Sandbox.new(%{
          "enabled" => true,
          "auto_allow_bash_if_sandboxed" => true,
          "excluded_commands" => ["nix"]
        })

      assert sandbox.enabled == true
      assert sandbox.auto_allow_bash_if_sandboxed == true
      assert sandbox.excluded_commands == ["nix"]
    end

    test "creates sandbox from camelCase string-keyed map including nested" do
      sandbox =
        Sandbox.new(%{
          "enabled" => true,
          "autoAllowBashIfSandboxed" => true,
          "allowUnsandboxedCommands" => false,
          "enableWeakerNestedSandbox" => true,
          "excludedCommands" => ["docker"],
          "ignoreViolations" => %{"fs" => ["deny"]},
          "ripgrep" => %{"command" => "/usr/bin/rg"},
          "filesystem" => %{"allowWrite" => ["/tmp"]},
          "network" => %{"allowedDomains" => ["example.com"]}
        })

      assert sandbox.enabled == true
      assert sandbox.auto_allow_bash_if_sandboxed == true
      assert sandbox.allow_unsandboxed_commands == false
      assert sandbox.enable_weaker_nested_sandbox == true
      assert sandbox.excluded_commands == ["docker"]
      assert sandbox.ignore_violations == %{"fs" => ["deny"]}
      assert sandbox.ripgrep == %{"command" => "/usr/bin/rg"}
      assert %Filesystem{allow_write: ["/tmp"]} = sandbox.filesystem
      assert %Network{allowed_domains: ["example.com"]} = sandbox.network
    end

    test "ignores unknown keys" do
      sandbox = Sandbox.new(enabled: true, bogus: "nope", foo: :bar)
      assert sandbox.enabled == true
    end

    test "filesystem nil stays nil" do
      sandbox = Sandbox.new(filesystem: nil)
      assert sandbox.filesystem == nil
    end

    test "network nil stays nil" do
      sandbox = Sandbox.new(network: nil)
      assert sandbox.network == nil
    end
  end

  describe "to_settings_map/1" do
    test "full conversion with nested structs" do
      sandbox =
        Sandbox.new(
          enabled: true,
          auto_allow_bash_if_sandboxed: true,
          allow_unsandboxed_commands: false,
          enable_weaker_nested_sandbox: true,
          excluded_commands: ["docker", "nix"],
          ignore_violations: %{"filesystem" => ["write_denied"]},
          ripgrep: %{command: "/usr/bin/rg"},
          filesystem: [allow_write: ["/tmp"], deny_read: ["~/.aws"]],
          network: [allowed_domains: ["*.example.com"], http_proxy_port: 8080]
        )

      result = Sandbox.to_settings_map(sandbox)

      assert result == %{
               "enabled" => true,
               "autoAllowBashIfSandboxed" => true,
               "allowUnsandboxedCommands" => false,
               "enableWeakerNestedSandbox" => true,
               "excludedCommands" => ["docker", "nix"],
               "ignoreViolations" => %{"filesystem" => ["write_denied"]},
               "ripgrep" => %{command: "/usr/bin/rg"},
               "filesystem" => %{
                 "allowWrite" => ["/tmp"],
                 "denyRead" => ["~/.aws"]
               },
               "network" => %{
                 "allowedDomains" => ["*.example.com"],
                 "httpProxyPort" => 8080
               }
             }
    end

    test "omits nil fields" do
      sandbox = Sandbox.new(enabled: true, excluded_commands: ["docker"])

      result = Sandbox.to_settings_map(sandbox)

      assert result == %{
               "enabled" => true,
               "excludedCommands" => ["docker"]
             }
    end

    test "returns empty map when all nil" do
      sandbox = Sandbox.new([])
      assert Sandbox.to_settings_map(sandbox) == %{}
    end

    test "omits empty nested structs" do
      sandbox = Sandbox.new(enabled: true, filesystem: [], network: [])

      result = Sandbox.to_settings_map(sandbox)

      assert result == %{"enabled" => true}
      refute Map.has_key?(result, "filesystem")
      refute Map.has_key?(result, "network")
    end
  end

  describe "Jason.Encoder" do
    test "round-trip with nested structs" do
      sandbox =
        Sandbox.new(
          enabled: true,
          auto_allow_bash_if_sandboxed: true,
          filesystem: [allow_write: ["/tmp"]],
          network: [allowed_domains: ["example.com"]]
        )

      decoded = sandbox |> Jason.encode!() |> Jason.decode!()

      assert decoded == %{
               "enabled" => true,
               "autoAllowBashIfSandboxed" => true,
               "filesystem" => %{"allowWrite" => ["/tmp"]},
               "network" => %{"allowedDomains" => ["example.com"]}
             }
    end

    test "omits nil fields" do
      sandbox = Sandbox.new(enabled: true)
      decoded = sandbox |> Jason.encode!() |> Jason.decode!()

      assert decoded == %{"enabled" => true}
      refute Map.has_key?(decoded, "filesystem")
      refute Map.has_key?(decoded, "network")
    end
  end

  describe "JSON.Encoder" do
    test "round-trip with nested structs" do
      sandbox =
        Sandbox.new(
          enabled: true,
          allow_unsandboxed_commands: false,
          filesystem: [deny_read: ["~/.aws"]],
          network: [allow_local_binding: true]
        )

      decoded = sandbox |> JSON.encode!() |> JSON.decode!()

      assert decoded == %{
               "enabled" => true,
               "allowUnsandboxedCommands" => false,
               "filesystem" => %{"denyRead" => ["~/.aws"]},
               "network" => %{"allowLocalBinding" => true}
             }
    end
  end
end
