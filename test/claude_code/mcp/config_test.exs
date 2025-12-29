defmodule ClaudeCode.MCP.ConfigTest do
  use ExUnit.Case

  alias ClaudeCode.MCP.Config

  describe "http_config/2" do
    test "generates basic HTTP config with required options" do
      config = Config.http_config("my-server", port: 9001)

      assert config == %{
               mcpServers: %{
                 "my-server" => %{url: "http://localhost:9001/sse"}
               }
             }
    end

    test "allows custom host" do
      config = Config.http_config("remote", port: 8080, host: "api.example.com")

      assert config.mcpServers["remote"].url == "http://api.example.com:8080/sse"
    end

    test "allows custom path" do
      config = Config.http_config("custom", port: 9001, path: "/mcp/events")

      assert config.mcpServers["custom"].url == "http://localhost:9001/mcp/events"
    end

    test "allows https scheme" do
      config = Config.http_config("secure", port: 443, scheme: "https", host: "secure.example.com")

      assert config.mcpServers["secure"].url == "https://secure.example.com:443/sse"
    end

    test "raises when port is missing" do
      assert_raise KeyError, fn ->
        Config.http_config("server", [])
      end
    end
  end

  describe "stdio_config/2" do
    test "generates basic stdio config" do
      config = Config.stdio_config("my-tool", command: "npx", args: ["@example/tool"])

      assert config == %{
               mcpServers: %{
                 "my-tool" => %{
                   command: "npx",
                   args: ["@example/tool"]
                 }
               }
             }
    end

    test "defaults to empty args" do
      config = Config.stdio_config("simple", command: "/usr/bin/mytool")

      assert config.mcpServers["simple"].args == []
    end

    test "includes env when provided" do
      config =
        Config.stdio_config("with-env",
          command: "node",
          args: ["server.js"],
          env: %{"API_KEY" => "secret", "DEBUG" => "true"}
        )

      assert config.mcpServers["with-env"].env == %{
               "API_KEY" => "secret",
               "DEBUG" => "true"
             }
    end

    test "omits env when empty" do
      config = Config.stdio_config("no-env", command: "tool", env: %{})

      refute Map.has_key?(config.mcpServers["no-env"], :env)
    end

    test "raises when command is missing" do
      assert_raise KeyError, fn ->
        Config.stdio_config("server", [])
      end
    end
  end

  describe "merge_configs/1" do
    test "merges multiple configs" do
      config1 = Config.http_config("server1", port: 9001)
      config2 = Config.http_config("server2", port: 9002)
      config3 = Config.stdio_config("server3", command: "tool")

      merged = Config.merge_configs([config1, config2, config3])

      assert merged.mcpServers |> Map.keys() |> Enum.sort() == ["server1", "server2", "server3"]
      assert merged.mcpServers["server1"].url == "http://localhost:9001/sse"
      assert merged.mcpServers["server2"].url == "http://localhost:9002/sse"
      assert merged.mcpServers["server3"].command == "tool"
    end

    test "handles empty list" do
      merged = Config.merge_configs([])

      assert merged == %{mcpServers: %{}}
    end

    test "later configs override earlier ones with same name" do
      config1 = Config.http_config("server", port: 9001)
      config2 = Config.http_config("server", port: 9002)

      merged = Config.merge_configs([config1, config2])

      assert merged.mcpServers["server"].url == "http://localhost:9002/sse"
    end
  end

  describe "write_temp_config/2" do
    test "writes config to temp file and returns path" do
      config = Config.http_config("test-server", port: 9001)

      {:ok, path} = Config.write_temp_config(config)

      assert File.exists?(path)
      assert String.ends_with?(path, ".json")

      content = File.read!(path)
      decoded = Jason.decode!(content)

      assert decoded["mcpServers"]["test-server"]["url"] == "http://localhost:9001/sse"

      # Cleanup
      File.rm(path)
    end

    test "uses custom prefix" do
      config = Config.http_config("test", port: 9001)

      {:ok, path} = Config.write_temp_config(config, prefix: "my_custom_prefix")

      assert String.contains?(path, "my_custom_prefix")

      File.rm(path)
    end

    test "uses custom directory" do
      config = Config.http_config("test", port: 9001)
      custom_dir = System.tmp_dir!()

      {:ok, path} = Config.write_temp_config(config, dir: custom_dir)

      assert String.starts_with?(path, custom_dir)

      File.rm(path)
    end
  end

  describe "to_json/2" do
    test "converts config to JSON string" do
      config = Config.http_config("server", port: 9001)

      {:ok, json} = Config.to_json(config)

      decoded = Jason.decode!(json)
      assert decoded["mcpServers"]["server"]["url"] == "http://localhost:9001/sse"
    end

    test "pretty prints when requested" do
      config = Config.http_config("server", port: 9001)

      {:ok, json} = Config.to_json(config, pretty: true)

      # Pretty printed JSON has newlines
      assert String.contains?(json, "\n")
    end

    test "compact by default" do
      config = Config.http_config("server", port: 9001)

      {:ok, json} = Config.to_json(config)

      # Compact JSON has no newlines
      refute String.contains?(json, "\n")
    end
  end
end
