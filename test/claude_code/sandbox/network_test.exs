defmodule ClaudeCode.Sandbox.NetworkTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Sandbox.Network

  describe "new/1" do
    test "creates network with all fields from keyword list" do
      net =
        Network.new(
          allowed_domains: ["*.example.com", "api.github.com"],
          allow_managed_domains_only: true,
          allow_unix_sockets: ["/run/user/1000/ssh-agent.sock"],
          allow_all_unix_sockets: false,
          allow_local_binding: true,
          http_proxy_port: 8080,
          socks_proxy_port: 1080
        )

      assert %Network{
               allowed_domains: ["*.example.com", "api.github.com"],
               allow_managed_domains_only: true,
               allow_unix_sockets: ["/run/user/1000/ssh-agent.sock"],
               allow_all_unix_sockets: false,
               allow_local_binding: true,
               http_proxy_port: 8080,
               socks_proxy_port: 1080
             } = net
    end

    test "creates network with no fields" do
      net = Network.new([])

      assert %Network{
               allowed_domains: nil,
               allow_managed_domains_only: nil,
               allow_unix_sockets: nil,
               allow_all_unix_sockets: nil,
               allow_local_binding: nil,
               http_proxy_port: nil,
               socks_proxy_port: nil
             } = net
    end

    test "creates network from atom-keyed map" do
      net = Network.new(%{allowed_domains: ["example.com"], http_proxy_port: 3128})
      assert net.allowed_domains == ["example.com"]
      assert net.http_proxy_port == 3128
      assert net.allow_managed_domains_only == nil
    end

    test "creates network from string-keyed map (snake_case)" do
      net =
        Network.new(%{
          "allowed_domains" => ["example.com"],
          "allow_local_binding" => true,
          "socks_proxy_port" => 1080
        })

      assert net.allowed_domains == ["example.com"]
      assert net.allow_local_binding == true
      assert net.socks_proxy_port == 1080
    end

    test "creates network from camelCase string-keyed map" do
      net =
        Network.new(%{
          "allowedDomains" => ["example.com"],
          "allowManagedDomainsOnly" => true,
          "allowUnixSockets" => ["/tmp/sock"],
          "allowAllUnixSockets" => false,
          "allowLocalBinding" => true,
          "httpProxyPort" => 8080,
          "socksProxyPort" => 1080
        })

      assert net.allowed_domains == ["example.com"]
      assert net.allow_managed_domains_only == true
      assert net.allow_unix_sockets == ["/tmp/sock"]
      assert net.allow_all_unix_sockets == false
      assert net.allow_local_binding == true
      assert net.http_proxy_port == 8080
      assert net.socks_proxy_port == 1080
    end

    test "ignores unknown keys" do
      net = Network.new(allowed_domains: ["example.com"], bogus: true, foo: "bar")
      assert net.allowed_domains == ["example.com"]
    end
  end

  describe "to_settings_map/1" do
    test "converts to camelCase map with all fields" do
      net =
        Network.new(
          allowed_domains: ["*.example.com"],
          allow_managed_domains_only: true,
          allow_unix_sockets: ["/tmp/sock"],
          allow_all_unix_sockets: false,
          allow_local_binding: true,
          http_proxy_port: 8080,
          socks_proxy_port: 1080
        )

      assert Network.to_settings_map(net) == %{
               "allowedDomains" => ["*.example.com"],
               "allowManagedDomainsOnly" => true,
               "allowUnixSockets" => ["/tmp/sock"],
               "allowAllUnixSockets" => false,
               "allowLocalBinding" => true,
               "httpProxyPort" => 8080,
               "socksProxyPort" => 1080
             }
    end

    test "omits nil fields" do
      net = Network.new(allowed_domains: ["example.com"], http_proxy_port: 8080)

      assert Network.to_settings_map(net) == %{
               "allowedDomains" => ["example.com"],
               "httpProxyPort" => 8080
             }
    end

    test "returns empty map when all fields nil" do
      net = Network.new([])
      assert Network.to_settings_map(net) == %{}
    end
  end

  describe "Jason.Encoder" do
    test "encodes to JSON and round-trips" do
      net = Network.new(allowed_domains: ["example.com"], allow_local_binding: true)
      decoded = net |> Jason.encode!() |> Jason.decode!()

      assert decoded == %{
               "allowed_domains" => ["example.com"],
               "allow_local_binding" => true
             }
    end
  end

  describe "JSON.Encoder" do
    test "encodes to JSON and round-trips" do
      net = Network.new(allowed_domains: ["example.com"], allow_local_binding: true)
      decoded = net |> JSON.encode!() |> JSON.decode!()

      assert decoded == %{
               "allowed_domains" => ["example.com"],
               "allow_local_binding" => true
             }
    end
  end
end
