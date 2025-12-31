defmodule ClaudeCode.OptionsTest do
  use ExUnit.Case

  alias ClaudeCode.Options

  describe "validate_session_options/1" do
    test "validates valid options" do
      opts = [
        api_key: "sk-ant-test",
        model: "opus",
        system_prompt: "You are helpful",
        allowed_tools: ["View", "GlobTool", "Bash(git:*)"],
        max_turns: 20,
        timeout: 60_000,
        permission_mode: :bypass_permissions,
        add_dir: ["/tmp", "/var/log"]
      ]

      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:api_key] == "sk-ant-test"
      assert validated[:model] == "opus"
      assert validated[:timeout] == 60_000
      assert validated[:permission_mode] == :bypass_permissions
      assert validated[:add_dir] == ["/tmp", "/var/log"]
    end

    test "applies default values" do
      opts = [api_key: "sk-ant-test"]

      assert {:ok, validated} = Options.validate_session_options(opts)
      # No model default - CLI handles its own defaults
      refute Keyword.has_key?(validated, :model)
      assert validated[:timeout] == 300_000
      assert validated[:permission_mode] == :default
    end

    test "allows missing api_key - CLI handles environment fallback" do
      opts = [model: "opus"]
      assert {:ok, validated} = Options.validate_session_options(opts)
      refute Keyword.has_key?(validated, :api_key)
      assert validated[:model] == "opus"
    end

    test "validates include_partial_messages option" do
      opts = [include_partial_messages: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:include_partial_messages] == true

      opts = [include_partial_messages: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:include_partial_messages] == false
    end

    test "defaults include_partial_messages to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:include_partial_messages] == false
    end

    test "validates mcp_servers option as a map" do
      opts = [
        mcp_servers: %{
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]},
          "filesystem" => %{command: "npx", args: ["-y", "@anthropic/mcp-filesystem"]}
        }
      ]

      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:mcp_servers]["playwright"][:command] == "npx"
      assert validated[:mcp_servers]["filesystem"][:args] == ["-y", "@anthropic/mcp-filesystem"]
    end

    test "validates mcp_servers with module atoms" do
      opts = [
        mcp_servers: %{
          "my-tools" => MyApp.MCPServer
        }
      ]

      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:mcp_servers]["my-tools"] == MyApp.MCPServer
    end

    test "validates mcp_servers with mixed modules and maps" do
      opts = [
        mcp_servers: %{
          "my-tools" => MyApp.MCPServer,
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}
        }
      ]

      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:mcp_servers]["my-tools"] == MyApp.MCPServer
      assert validated[:mcp_servers]["playwright"][:command] == "npx"
    end

    test "accepts explicit api_key when provided" do
      opts = [api_key: "explicit-key", model: "opus"]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:api_key] == "explicit-key"
      assert validated[:model] == "opus"
    end

    test "validates fallback_model option" do
      opts = [model: "opus", fallback_model: "sonnet"]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:model] == "opus"
      assert validated[:fallback_model] == "sonnet"
    end

    test "rejects invalid timeout type" do
      opts = [api_key: "sk-ant-test", timeout: "not_a_number"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_session_options(opts)
    end

    test "rejects unknown options" do
      opts = [api_key: "sk-ant-test", unknown_option: "value"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_session_options(opts)
    end

    test "validates json_schema as a map" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      opts = [json_schema: schema]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:json_schema] == schema
    end

    test "validates json_schema as a string" do
      schema = ~s({"type":"object","properties":{"name":{"type":"string"}}})
      opts = [json_schema: schema]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:json_schema] == schema
    end

    test "validates max_budget_usd as float" do
      opts = [max_budget_usd: 10.50]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:max_budget_usd] == 10.50
    end

    test "validates max_budget_usd as integer" do
      opts = [max_budget_usd: 25]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:max_budget_usd] == 25
    end

    test "validates agent option" do
      opts = [agent: "code-reviewer"]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:agent] == "code-reviewer"
    end

    test "validates betas option" do
      opts = [betas: ["feature-x", "feature-y"]]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:betas] == ["feature-x", "feature-y"]
    end

    test "validates tools option as list" do
      opts = [tools: ["Bash", "Edit", "Read"]]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:tools] == ["Bash", "Edit", "Read"]
    end

    test "validates tools option with empty list to disable all" do
      opts = [tools: []]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:tools] == []
    end

    test "validates tools option with :default atom" do
      opts = [tools: :default]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:tools] == :default
    end
  end

  describe "validate_query_options/1" do
    test "validates valid options" do
      opts = [
        system_prompt: "Focus on performance",
        timeout: 120_000,
        allowed_tools: ["Bash(git:*)"],
        permission_mode: :bypass_permissions,
        add_dir: ["/home/user/docs"],
        output_format: "stream-json"
      ]

      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:system_prompt] == "Focus on performance"
      assert validated[:timeout] == 120_000
      assert validated[:allowed_tools] == ["Bash(git:*)"]
      assert validated[:permission_mode] == :bypass_permissions
      assert validated[:add_dir] == ["/home/user/docs"]
      assert validated[:output_format] == "stream-json"
    end

    test "accepts empty options" do
      assert {:ok, []} = Options.validate_query_options([])
    end

    test "validates include_partial_messages in query options" do
      opts = [include_partial_messages: true]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:include_partial_messages] == true
    end

    test "validates mcp_servers in query options" do
      opts = [
        mcp_servers: %{
          "custom-server" => %{command: "node", args: ["server.js"]}
        }
      ]

      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:mcp_servers]["custom-server"][:command] == "node"
    end

    test "validates model and fallback_model in query options" do
      opts = [model: "opus", fallback_model: "sonnet"]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:model] == "opus"
      assert validated[:fallback_model] == "sonnet"
    end

    test "rejects invalid options" do
      opts = [invalid_option: "value"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_query_options(opts)
    end

    test "validates json_schema in query options" do
      schema = %{"type" => "object", "properties" => %{"result" => %{"type" => "number"}}}
      opts = [json_schema: schema]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:json_schema] == schema
    end

    test "validates max_budget_usd in query options" do
      opts = [max_budget_usd: 5.00]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:max_budget_usd] == 5.00
    end

    test "validates agent in query options" do
      opts = [agent: "debugger"]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:agent] == "debugger"
    end

    test "validates betas in query options" do
      opts = [betas: ["beta-feature"]]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:betas] == ["beta-feature"]
    end

    test "validates tools in query options" do
      opts = [tools: ["Read", "Write"]]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:tools] == ["Read", "Write"]
    end
  end

  describe "to_cli_args/1" do
    test "converts system_prompt to --system-prompt" do
      opts = [system_prompt: "You are helpful"]

      args = Options.to_cli_args(opts)
      assert "--system-prompt" in args
      assert "You are helpful" in args
    end

    test "converts allowed_tools to --allowedTools" do
      opts = [allowed_tools: ["View", "GlobTool", "Bash(git:*)"]]

      args = Options.to_cli_args(opts)
      assert "--allowedTools" in args
      assert "View,GlobTool,Bash(git:*)" in args
    end

    test "converts max_turns to --max-turns" do
      opts = [max_turns: 20]

      args = Options.to_cli_args(opts)
      assert "--max-turns" in args
      assert "20" in args
    end

    test "converts max_budget_usd to --max-budget-usd" do
      opts = [max_budget_usd: 10.50]

      args = Options.to_cli_args(opts)
      assert "--max-budget-usd" in args
      assert "10.5" in args
    end

    test "converts max_budget_usd integer to --max-budget-usd" do
      opts = [max_budget_usd: 25]

      args = Options.to_cli_args(opts)
      assert "--max-budget-usd" in args
      assert "25" in args
    end

    test "converts agent to --agent" do
      opts = [agent: "code-reviewer"]

      args = Options.to_cli_args(opts)
      assert "--agent" in args
      assert "code-reviewer" in args
    end

    test "converts betas to multiple --betas flags" do
      opts = [betas: ["feature-x", "feature-y"]]

      args = Options.to_cli_args(opts)
      assert "--betas" in args
      assert "feature-x" in args
      assert "feature-y" in args
      # Should have multiple --betas flags
      betas_count = Enum.count(args, &(&1 == "--betas"))
      assert betas_count == 2
    end

    test "handles empty betas list" do
      opts = [betas: []]

      args = Options.to_cli_args(opts)
      refute "--betas" in args
    end

    test "converts tools to --tools as CSV" do
      opts = [tools: ["Bash", "Edit", "Read"]]

      args = Options.to_cli_args(opts)
      assert "--tools" in args
      assert "Bash,Edit,Read" in args
    end

    test "converts empty tools list to disable all tools" do
      opts = [tools: []]

      args = Options.to_cli_args(opts)
      assert "--tools" in args
      assert "" in args
    end

    test "converts tools :default to --tools default" do
      opts = [tools: :default]

      args = Options.to_cli_args(opts)
      assert "--tools" in args
      assert "default" in args
    end

    test "converts fallback_model to --fallback-model" do
      opts = [fallback_model: "sonnet"]

      args = Options.to_cli_args(opts)
      assert "--fallback-model" in args
      assert "sonnet" in args
    end

    test "converts model and fallback_model together" do
      opts = [model: "opus", fallback_model: "sonnet"]

      args = Options.to_cli_args(opts)
      assert "--model" in args
      assert "opus" in args
      assert "--fallback-model" in args
      assert "sonnet" in args
    end

    test "cwd option is not converted to CLI flag" do
      opts = [cwd: "/tmp"]

      args = Options.to_cli_args(opts)
      refute "--cwd" in args
      refute "/tmp" in args
    end

    test "does not convert timeout to CLI flag" do
      opts = [timeout: 120_000]

      args = Options.to_cli_args(opts)
      refute "--timeout" in args
      refute "120000" in args
    end

    test "ignores internal options (api_key, name, timeout)" do
      opts = [api_key: "sk-ant-test", name: :session, timeout: 60_000, model: "opus"]

      args = Options.to_cli_args(opts)
      refute "--api-key" in args
      refute "--name" in args
      refute "--timeout" in args
      refute "sk-ant-test" in args
      refute ":session" in args
      refute "60000" in args
      # But model should still be included
      assert "--model" in args
      assert "opus" in args
    end

    test "ignores nil values" do
      opts = [system_prompt: nil, model: "opus"]

      args = Options.to_cli_args(opts)
      refute "--system-prompt" in args
      refute nil in args
    end

    test "converts permission_mode to --permission-mode" do
      opts = [permission_mode: :accept_edits]

      args = Options.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "acceptEdits" in args
    end

    test "converts permission_mode bypass_permissions to --permission-mode bypassPermissions" do
      opts = [permission_mode: :bypass_permissions]

      args = Options.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "bypassPermissions" in args
    end

    test "ignores permission_mode when default" do
      opts = [permission_mode: :default]

      args = Options.to_cli_args(opts)
      refute "--permission-mode" in args
      refute "default" in args
    end

    test "converts add_dir to --add-dir" do
      opts = [add_dir: ["/tmp", "/var/log", "/home/user/docs"]]

      args = Options.to_cli_args(opts)
      assert "--add-dir" in args
      assert "/tmp" in args
      assert "--add-dir" in args
      assert "/var/log" in args
      assert "--add-dir" in args
      assert "/home/user/docs" in args
    end

    test "handles empty add_dir list" do
      opts = [add_dir: []]

      args = Options.to_cli_args(opts)
      refute "--add-dir" in args
    end

    test "handles single add_dir entry" do
      opts = [add_dir: ["/single/path"]]

      args = Options.to_cli_args(opts)
      assert "--add-dir" in args
      assert "/single/path" in args
    end

    test "converts output_format to --output-format" do
      opts = [output_format: "stream-json"]

      args = Options.to_cli_args(opts)
      assert "--output-format" in args
      assert "stream-json" in args
    end

    test "converts output_format with different values" do
      # Test text format
      opts = [output_format: "text"]
      args = Options.to_cli_args(opts)
      assert "--output-format" in args
      assert "text" in args

      # Test json format
      opts = [output_format: "json"]
      args = Options.to_cli_args(opts)
      assert "--output-format" in args
      assert "json" in args
    end

    test "converts json_schema map to JSON-encoded --json-schema" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"]}
      opts = [json_schema: schema]

      args = Options.to_cli_args(opts)
      assert "--json-schema" in args

      # Find the JSON value
      schema_index = Enum.find_index(args, &(&1 == "--json-schema"))
      json_value = Enum.at(args, schema_index + 1)

      # Decode and verify
      decoded = Jason.decode!(json_value)
      assert decoded["type"] == "object"
      assert decoded["properties"]["name"]["type"] == "string"
      assert decoded["required"] == ["name"]
    end

    test "converts json_schema string directly to --json-schema" do
      schema = ~s({"type":"object","properties":{"name":{"type":"string"}}})
      opts = [json_schema: schema]

      args = Options.to_cli_args(opts)
      assert "--json-schema" in args
      assert schema in args
    end

    test "converts json_schema with nested structures" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "users" => %{
            "type" => "array",
            "items" => %{"type" => "object", "properties" => %{"id" => %{"type" => "integer"}}}
          }
        }
      }

      opts = [json_schema: schema]

      args = Options.to_cli_args(opts)
      assert "--json-schema" in args

      schema_index = Enum.find_index(args, &(&1 == "--json-schema"))
      json_value = Enum.at(args, schema_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["properties"]["users"]["type"] == "array"
      assert decoded["properties"]["users"]["items"]["properties"]["id"]["type"] == "integer"
    end

    test "converts settings string to --settings" do
      opts = [settings: "/path/to/settings.json"]

      args = Options.to_cli_args(opts)
      assert "--settings" in args
      assert "/path/to/settings.json" in args
    end

    test "converts settings map to JSON-encoded --settings" do
      opts = [settings: %{"feature" => true, "timeout" => 5000}]

      args = Options.to_cli_args(opts)
      assert "--settings" in args

      # Find the JSON value
      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)

      # Decode and verify
      decoded = Jason.decode!(json_value)
      assert decoded["feature"] == true
      assert decoded["timeout"] == 5000
    end

    test "converts settings with nested map to JSON" do
      opts = [settings: %{"nested" => %{"key" => "value"}, "list" => [1, 2, 3]}]

      args = Options.to_cli_args(opts)
      assert "--settings" in args

      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["nested"]["key"] == "value"
      assert decoded["list"] == [1, 2, 3]
    end

    test "converts setting_sources to --setting-sources as CSV" do
      opts = [setting_sources: ["user", "project", "local"]]

      args = Options.to_cli_args(opts)
      assert "--setting-sources" in args
      assert "user,project,local" in args
    end

    test "converts single setting_source to --setting-sources" do
      opts = [setting_sources: ["user"]]

      args = Options.to_cli_args(opts)
      assert "--setting-sources" in args
      assert "user" in args
    end

    test "handles empty setting_sources list" do
      opts = [setting_sources: []]

      args = Options.to_cli_args(opts)
      assert "--setting-sources" in args
      assert "" in args
    end

    test "converts agents map to JSON-encoded --agents" do
      opts = [
        agents: %{
          "code-reviewer" => %{
            "description" => "Reviews code for quality",
            "prompt" => "You are a code reviewer",
            "tools" => ["Read", "Edit"],
            "model" => "sonnet"
          }
        }
      ]

      args = Options.to_cli_args(opts)
      assert "--agents" in args

      # Find the JSON value
      agents_index = Enum.find_index(args, &(&1 == "--agents"))
      json_value = Enum.at(args, agents_index + 1)

      # Decode and verify
      decoded = Jason.decode!(json_value)
      assert decoded["code-reviewer"]["description"] == "Reviews code for quality"
      assert decoded["code-reviewer"]["prompt"] == "You are a code reviewer"
      assert decoded["code-reviewer"]["tools"] == ["Read", "Edit"]
      assert decoded["code-reviewer"]["model"] == "sonnet"
    end

    test "converts multiple agents to JSON" do
      opts = [
        agents: %{
          "code-reviewer" => %{
            "description" => "Reviews code",
            "prompt" => "You are a reviewer"
          },
          "debugger" => %{
            "description" => "Debugs code",
            "prompt" => "You are a debugger",
            "tools" => ["Read", "Bash"]
          }
        }
      ]

      args = Options.to_cli_args(opts)
      assert "--agents" in args

      agents_index = Enum.find_index(args, &(&1 == "--agents"))
      json_value = Enum.at(args, agents_index + 1)

      decoded = Jason.decode!(json_value)
      assert Map.has_key?(decoded, "code-reviewer")
      assert Map.has_key?(decoded, "debugger")
      assert decoded["debugger"]["tools"] == ["Read", "Bash"]
    end

    test "converts mcp_servers map to JSON-encoded --mcp-servers" do
      opts = [
        mcp_servers: %{
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}
        }
      ]

      args = Options.to_cli_args(opts)
      assert "--mcp-servers" in args

      # Find the JSON value
      mcp_index = Enum.find_index(args, &(&1 == "--mcp-servers"))
      json_value = Enum.at(args, mcp_index + 1)

      # Decode and verify
      decoded = Jason.decode!(json_value)
      assert decoded["playwright"]["command"] == "npx"
      assert decoded["playwright"]["args"] == ["@playwright/mcp@latest"]
    end

    test "converts multiple mcp_servers to JSON" do
      opts = [
        mcp_servers: %{
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]},
          "filesystem" => %{
            command: "npx",
            args: ["-y", "@anthropic/mcp-filesystem"],
            env: %{"HOME" => "/tmp"}
          }
        }
      ]

      args = Options.to_cli_args(opts)
      assert "--mcp-servers" in args

      mcp_index = Enum.find_index(args, &(&1 == "--mcp-servers"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)
      assert Map.has_key?(decoded, "playwright")
      assert Map.has_key?(decoded, "filesystem")
      assert decoded["filesystem"]["env"]["HOME"] == "/tmp"
    end

    test "expands module atoms in mcp_servers to stdio command config" do
      opts = [
        mcp_servers: %{
          "my-tools" => MyApp.MCPServer
        }
      ]

      args = Options.to_cli_args(opts)
      assert "--mcp-servers" in args

      mcp_index = Enum.find_index(args, &(&1 == "--mcp-servers"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["my-tools"]["command"] == "mix"
      assert decoded["my-tools"]["args"] == ["run", "--no-halt", "-e", "MyApp.MCPServer.start_link(transport: :stdio)"]
      assert decoded["my-tools"]["env"]["MIX_ENV"] == "prod"
    end

    test "expands mixed modules and maps in mcp_servers" do
      opts = [
        mcp_servers: %{
          "my-tools" => MyApp.MCPServer,
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}
        }
      ]

      args = Options.to_cli_args(opts)
      assert "--mcp-servers" in args

      mcp_index = Enum.find_index(args, &(&1 == "--mcp-servers"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)

      # Module was expanded
      assert decoded["my-tools"]["command"] == "mix"
      assert decoded["my-tools"]["args"] == ["run", "--no-halt", "-e", "MyApp.MCPServer.start_link(transport: :stdio)"]

      # Map config was preserved
      assert decoded["playwright"]["command"] == "npx"
      assert decoded["playwright"]["args"] == ["@playwright/mcp@latest"]
    end

    test "converts include_partial_messages true to --include-partial-messages" do
      opts = [include_partial_messages: true]

      args = Options.to_cli_args(opts)
      assert "--include-partial-messages" in args
      # Boolean flag should not have a value
      refute "true" in args
    end

    test "does not add flag when include_partial_messages is false" do
      opts = [include_partial_messages: false]

      args = Options.to_cli_args(opts)
      refute "--include-partial-messages" in args
    end

    test "combines include_partial_messages with other options" do
      opts = [
        include_partial_messages: true,
        model: "opus",
        max_turns: 10
      ]

      args = Options.to_cli_args(opts)
      assert "--include-partial-messages" in args
      assert "--model" in args
      assert "opus" in args
      assert "--max-turns" in args
      assert "10" in args
    end
  end

  describe "merge_options/2" do
    test "merges session and query options with query taking precedence" do
      session_opts = [
        system_prompt: "You are helpful",
        timeout: 60_000,
        allowed_tools: ["View", "GlobTool"],
        add_dir: ["/tmp", "/var/log"]
      ]

      query_opts = [
        system_prompt: "Focus on performance",
        timeout: 120_000,
        add_dir: ["/home/user/custom"]
      ]

      merged = Options.merge_options(session_opts, query_opts)

      assert merged[:system_prompt] == "Focus on performance"
      assert merged[:timeout] == 120_000
      assert merged[:allowed_tools] == ["View", "GlobTool"]
      assert merged[:add_dir] == ["/home/user/custom"]
    end

    test "preserves session options when query options are empty" do
      session_opts = [
        system_prompt: "You are helpful",
        timeout: 60_000,
        add_dir: ["/data"]
      ]

      query_opts = []

      merged = Options.merge_options(session_opts, query_opts)

      assert merged[:system_prompt] == "You are helpful"
      assert merged[:timeout] == 60_000
      assert merged[:add_dir] == ["/data"]
    end

    test "uses query options when session options are empty" do
      session_opts = []

      query_opts = [
        system_prompt: "Focus on performance",
        timeout: 120_000
      ]

      merged = Options.merge_options(session_opts, query_opts)

      assert merged[:system_prompt] == "Focus on performance"
      assert merged[:timeout] == 120_000
    end
  end

  describe "get_app_config/0" do
    test "returns application config for claude_code" do
      # Mock application config
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :timeout, 180_000)

      config = Options.get_app_config()

      assert config[:model] == "opus"
      assert config[:timeout] == 180_000

      # Cleanup
      Application.delete_env(:claude_code, :model)
      Application.delete_env(:claude_code, :timeout)
    end

    test "returns empty list when no config is set" do
      config = Options.get_app_config()
      assert is_list(config)
    end
  end

  describe "apply_app_config_defaults/1" do
    test "merges app config with session opts, session opts take precedence" do
      # Set app config
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :timeout, 180_000)

      try do
        result = Options.apply_app_config_defaults(timeout: 60_000)
        assert result[:model] == "opus"
        assert result[:timeout] == 60_000
      after
        Application.delete_env(:claude_code, :model)
        Application.delete_env(:claude_code, :timeout)
      end
    end

    test "returns session opts when no app config" do
      result = Options.apply_app_config_defaults(model: "sonnet")
      assert result[:model] == "sonnet"
    end
  end
end
