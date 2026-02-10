defmodule ClaudeCode.CLI.CommandTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.CLI.Command

  describe "build_args/3" do
    test "includes required flags" do
      args = Command.build_args("hello", [], nil)

      assert "--output-format" in args
      assert "stream-json" in args
      assert "--verbose" in args
      assert "--print" in args
      assert "hello" in args
    end

    test "appends prompt as the last argument" do
      args = Command.build_args("my prompt", [model: "opus"], nil)

      assert List.last(args) == "my prompt"
    end

    test "adds --resume when session_id is provided" do
      args = Command.build_args("hello", [], "sess-123")

      assert "--resume" in args
      assert "sess-123" in args
    end

    test "omits --resume when session_id is nil" do
      args = Command.build_args("hello", [], nil)

      refute "--resume" in args
    end

    test "places --resume before option args" do
      args = Command.build_args("hello", [model: "opus"], "sess-123")

      resume_pos = Enum.find_index(args, &(&1 == "--resume"))
      model_pos = Enum.find_index(args, &(&1 == "--model"))

      assert resume_pos < model_pos
    end

    test "converts options to CLI flags" do
      args = Command.build_args("hello", [model: "opus", max_turns: 10], nil)

      assert "--model" in args
      assert "opus" in args
      assert "--max-turns" in args
      assert "10" in args
    end

    test "ignores internal options" do
      args = Command.build_args("hello", [api_key: "sk-test", timeout: 60_000, name: :my_session], nil)

      refute "--api-key" in args
      refute "--timeout" in args
      refute "--name" in args
    end
  end

  describe "to_cli_args/1" do
    test "converts system_prompt to --system-prompt" do
      opts = [system_prompt: "You are helpful"]

      args = Command.to_cli_args(opts)
      assert "--system-prompt" in args
      assert "You are helpful" in args
    end

    test "converts allowed_tools to --allowedTools" do
      opts = [allowed_tools: ["View", "GlobTool", "Bash(git:*)"]]

      args = Command.to_cli_args(opts)
      assert "--allowedTools" in args
      assert "View,GlobTool,Bash(git:*)" in args
    end

    test "converts max_turns to --max-turns" do
      opts = [max_turns: 20]

      args = Command.to_cli_args(opts)
      assert "--max-turns" in args
      assert "20" in args
    end

    test "converts max_budget_usd to --max-budget-usd" do
      opts = [max_budget_usd: 10.50]

      args = Command.to_cli_args(opts)
      assert "--max-budget-usd" in args
      assert "10.5" in args
    end

    test "converts max_budget_usd integer to --max-budget-usd" do
      opts = [max_budget_usd: 25]

      args = Command.to_cli_args(opts)
      assert "--max-budget-usd" in args
      assert "25" in args
    end

    test "converts agent to --agent" do
      opts = [agent: "code-reviewer"]

      args = Command.to_cli_args(opts)
      assert "--agent" in args
      assert "code-reviewer" in args
    end

    test "converts betas to multiple --betas flags" do
      opts = [betas: ["feature-x", "feature-y"]]

      args = Command.to_cli_args(opts)
      assert "--betas" in args
      assert "feature-x" in args
      assert "feature-y" in args
      # Should have multiple --betas flags
      betas_count = Enum.count(args, &(&1 == "--betas"))
      assert betas_count == 2
    end

    test "handles empty betas list" do
      opts = [betas: []]

      args = Command.to_cli_args(opts)
      refute "--betas" in args
    end

    test "converts tools to --tools as CSV" do
      opts = [tools: ["Bash", "Edit", "Read"]]

      args = Command.to_cli_args(opts)
      assert "--tools" in args
      assert "Bash,Edit,Read" in args
    end

    test "converts empty tools list to disable all tools" do
      opts = [tools: []]

      args = Command.to_cli_args(opts)
      assert "--tools" in args
      assert "" in args
    end

    test "converts tools :default to --tools default" do
      opts = [tools: :default]

      args = Command.to_cli_args(opts)
      assert "--tools" in args
      assert "default" in args
    end

    test "converts fallback_model to --fallback-model" do
      opts = [fallback_model: "sonnet"]

      args = Command.to_cli_args(opts)
      assert "--fallback-model" in args
      assert "sonnet" in args
    end

    test "converts model and fallback_model together" do
      opts = [model: "opus", fallback_model: "sonnet"]

      args = Command.to_cli_args(opts)
      assert "--model" in args
      assert "opus" in args
      assert "--fallback-model" in args
      assert "sonnet" in args
    end

    test "cwd option is not converted to CLI flag" do
      opts = [cwd: "/tmp"]

      args = Command.to_cli_args(opts)
      refute "--cwd" in args
      refute "/tmp" in args
    end

    test "does not convert timeout to CLI flag" do
      opts = [timeout: 120_000]

      args = Command.to_cli_args(opts)
      refute "--timeout" in args
      refute "120000" in args
    end

    test "ignores internal options (api_key, name, timeout)" do
      opts = [api_key: "sk-ant-test", name: :session, timeout: 60_000, model: "opus"]

      args = Command.to_cli_args(opts)
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

      args = Command.to_cli_args(opts)
      refute "--system-prompt" in args
      refute nil in args
    end

    test "converts permission_mode to --permission-mode" do
      opts = [permission_mode: :accept_edits]

      args = Command.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "acceptEdits" in args
    end

    test "converts permission_mode bypass_permissions to --permission-mode bypassPermissions" do
      opts = [permission_mode: :bypass_permissions]

      args = Command.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "bypassPermissions" in args
    end

    test "converts permission_mode default to --permission-mode default" do
      opts = [permission_mode: :default]

      args = Command.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "default" in args
    end

    test "converts permission_mode delegate to --permission-mode delegate" do
      opts = [permission_mode: :delegate]

      args = Command.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "delegate" in args
    end

    test "converts permission_mode dont_ask to --permission-mode dontAsk" do
      opts = [permission_mode: :dont_ask]

      args = Command.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "dontAsk" in args
    end

    test "converts permission_mode plan to --permission-mode plan" do
      opts = [permission_mode: :plan]

      args = Command.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "plan" in args
    end

    test "converts add_dir to --add-dir" do
      opts = [add_dir: ["/tmp", "/var/log", "/home/user/docs"]]

      args = Command.to_cli_args(opts)
      assert "--add-dir" in args
      assert "/tmp" in args
      assert "--add-dir" in args
      assert "/var/log" in args
      assert "--add-dir" in args
      assert "/home/user/docs" in args
    end

    test "handles empty add_dir list" do
      opts = [add_dir: []]

      args = Command.to_cli_args(opts)
      refute "--add-dir" in args
    end

    test "handles single add_dir entry" do
      opts = [add_dir: ["/single/path"]]

      args = Command.to_cli_args(opts)
      assert "--add-dir" in args
      assert "/single/path" in args
    end

    test "converts output_format with json_schema to --json-schema" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"]}
      opts = [output_format: %{type: :json_schema, schema: schema}]

      args = Command.to_cli_args(opts)
      assert "--json-schema" in args

      # Find the JSON value
      schema_index = Enum.find_index(args, &(&1 == "--json-schema"))
      json_value = Enum.at(args, schema_index + 1)

      # Decode and verify - only the schema is passed, not the wrapper
      decoded = Jason.decode!(json_value)
      assert decoded["type"] == "object"
      assert decoded["properties"]["name"]["type"] == "string"
      assert decoded["required"] == ["name"]
    end

    test "converts output_format with nested schema structures" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "users" => %{
            "type" => "array",
            "items" => %{"type" => "object", "properties" => %{"id" => %{"type" => "integer"}}}
          }
        }
      }

      opts = [output_format: %{type: :json_schema, schema: schema}]

      args = Command.to_cli_args(opts)
      assert "--json-schema" in args

      schema_index = Enum.find_index(args, &(&1 == "--json-schema"))
      json_value = Enum.at(args, schema_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["properties"]["users"]["type"] == "array"
      assert decoded["properties"]["users"]["items"]["properties"]["id"]["type"] == "integer"
    end

    test "ignores output_format with unsupported type" do
      opts = [output_format: %{type: :other, data: "something"}]

      args = Command.to_cli_args(opts)
      refute "--json-schema" in args
    end

    test "converts settings string to --settings" do
      opts = [settings: "/path/to/settings.json"]

      args = Command.to_cli_args(opts)
      assert "--settings" in args
      assert "/path/to/settings.json" in args
    end

    test "converts settings map to JSON-encoded --settings" do
      opts = [settings: %{"feature" => true, "timeout" => 5000}]

      args = Command.to_cli_args(opts)
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

      args = Command.to_cli_args(opts)
      assert "--settings" in args

      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["nested"]["key"] == "value"
      assert decoded["list"] == [1, 2, 3]
    end

    test "converts setting_sources to --setting-sources as CSV" do
      opts = [setting_sources: ["user", "project", "local"]]

      args = Command.to_cli_args(opts)
      assert "--setting-sources" in args
      assert "user,project,local" in args
    end

    test "converts single setting_source to --setting-sources" do
      opts = [setting_sources: ["user"]]

      args = Command.to_cli_args(opts)
      assert "--setting-sources" in args
      assert "user" in args
    end

    test "handles empty setting_sources list" do
      opts = [setting_sources: []]

      args = Command.to_cli_args(opts)
      assert "--setting-sources" in args
      assert "" in args
    end

    test "agents option is not converted to CLI flag (sent via control protocol)" do
      opts = [
        agents: %{
          "code-reviewer" => %{
            "description" => "Reviews code",
            "prompt" => "You are a reviewer"
          }
        }
      ]

      args = Command.to_cli_args(opts)
      refute "--agents" in args
    end

    test "converts mcp_servers map to JSON-encoded --mcp-config" do
      opts = [
        mcp_servers: %{
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}
        }
      ]

      args = Command.to_cli_args(opts)
      assert "--mcp-config" in args

      # Find the JSON value
      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)

      # Decode and verify - JSON has mcpServers wrapper
      decoded = Jason.decode!(json_value)
      assert decoded["mcpServers"]["playwright"]["command"] == "npx"
      assert decoded["mcpServers"]["playwright"]["args"] == ["@playwright/mcp@latest"]
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

      args = Command.to_cli_args(opts)
      assert "--mcp-config" in args

      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)
      assert Map.has_key?(decoded["mcpServers"], "playwright")
      assert Map.has_key?(decoded["mcpServers"], "filesystem")
      assert decoded["mcpServers"]["filesystem"]["env"]["HOME"] == "/tmp"
    end

    test "expands module atoms in mcp_servers to stdio command config" do
      opts = [
        mcp_servers: %{
          "my-tools" => MyApp.MCPServer
        }
      ]

      args = Command.to_cli_args(opts)
      assert "--mcp-config" in args

      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["mcpServers"]["my-tools"]["command"] == "mix"

      assert decoded["mcpServers"]["my-tools"]["args"] == [
               "run",
               "--no-halt",
               "-e",
               "MyApp.MCPServer.start_link(transport: :stdio)"
             ]

      assert decoded["mcpServers"]["my-tools"]["env"]["MIX_ENV"] == "prod"
    end

    test "expands mixed modules and maps in mcp_servers" do
      opts = [
        mcp_servers: %{
          "my-tools" => MyApp.MCPServer,
          "playwright" => %{command: "npx", args: ["@playwright/mcp@latest"]}
        }
      ]

      args = Command.to_cli_args(opts)
      assert "--mcp-config" in args

      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)

      # Module was expanded
      assert decoded["mcpServers"]["my-tools"]["command"] == "mix"

      assert decoded["mcpServers"]["my-tools"]["args"] == [
               "run",
               "--no-halt",
               "-e",
               "MyApp.MCPServer.start_link(transport: :stdio)"
             ]

      # Map config was preserved
      assert decoded["mcpServers"]["playwright"]["command"] == "npx"
      assert decoded["mcpServers"]["playwright"]["args"] == ["@playwright/mcp@latest"]
    end

    test "expands module map with custom env in mcp_servers (atom keys)" do
      opts = [
        mcp_servers: %{
          "my-tools" => %{module: MyApp.MCPServer, env: %{"DEBUG" => "1", "LOG_LEVEL" => "debug"}}
        }
      ]

      args = Command.to_cli_args(opts)
      assert "--mcp-config" in args

      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["mcpServers"]["my-tools"]["command"] == "mix"

      assert decoded["mcpServers"]["my-tools"]["args"] == [
               "run",
               "--no-halt",
               "-e",
               "MyApp.MCPServer.start_link(transport: :stdio)"
             ]

      # Custom env merged with defaults
      assert decoded["mcpServers"]["my-tools"]["env"]["MIX_ENV"] == "prod"
      assert decoded["mcpServers"]["my-tools"]["env"]["DEBUG"] == "1"
      assert decoded["mcpServers"]["my-tools"]["env"]["LOG_LEVEL"] == "debug"
    end

    test "expands module map with custom env in mcp_servers (string keys)" do
      opts = [
        mcp_servers: %{
          "my-tools" => %{"module" => MyApp.MCPServer, "env" => %{"DEBUG" => "1"}}
        }
      ]

      args = Command.to_cli_args(opts)
      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["mcpServers"]["my-tools"]["command"] == "mix"
      assert decoded["mcpServers"]["my-tools"]["env"]["MIX_ENV"] == "prod"
      assert decoded["mcpServers"]["my-tools"]["env"]["DEBUG"] == "1"
    end

    test "custom env can override MIX_ENV in module map" do
      opts = [
        mcp_servers: %{
          "my-tools" => %{module: MyApp.MCPServer, env: %{"MIX_ENV" => "dev"}}
        }
      ]

      args = Command.to_cli_args(opts)
      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["mcpServers"]["my-tools"]["env"]["MIX_ENV"] == "dev"
    end

    test "converts include_partial_messages true to --include-partial-messages" do
      opts = [include_partial_messages: true]

      args = Command.to_cli_args(opts)
      assert "--include-partial-messages" in args
      # Boolean flag should not have a value
      refute "true" in args
    end

    test "does not add flag when include_partial_messages is false" do
      opts = [include_partial_messages: false]

      args = Command.to_cli_args(opts)
      refute "--include-partial-messages" in args
    end

    test "combines include_partial_messages with other options" do
      opts = [
        include_partial_messages: true,
        model: "opus",
        max_turns: 10
      ]

      args = Command.to_cli_args(opts)
      assert "--include-partial-messages" in args
      assert "--model" in args
      assert "opus" in args
      assert "--max-turns" in args
      assert "10" in args
    end

    test "converts strict_mcp_config true to --strict-mcp-config" do
      opts = [strict_mcp_config: true]

      args = Command.to_cli_args(opts)
      assert "--strict-mcp-config" in args
      # Boolean flag should not have a value
      refute "true" in args
    end

    test "does not add flag when strict_mcp_config is false" do
      opts = [strict_mcp_config: false]

      args = Command.to_cli_args(opts)
      refute "--strict-mcp-config" in args
    end

    test "converts allow_dangerously_skip_permissions true to --allow-dangerously-skip-permissions" do
      opts = [allow_dangerously_skip_permissions: true]

      args = Command.to_cli_args(opts)
      assert "--allow-dangerously-skip-permissions" in args
      refute "true" in args
    end

    test "does not add flag when allow_dangerously_skip_permissions is false" do
      opts = [allow_dangerously_skip_permissions: false]

      args = Command.to_cli_args(opts)
      refute "--allow-dangerously-skip-permissions" in args
    end

    test "converts disable_slash_commands true to --disable-slash-commands" do
      opts = [disable_slash_commands: true]

      args = Command.to_cli_args(opts)
      assert "--disable-slash-commands" in args
      refute "true" in args
    end

    test "does not add flag when disable_slash_commands is false" do
      opts = [disable_slash_commands: false]

      args = Command.to_cli_args(opts)
      refute "--disable-slash-commands" in args
    end

    test "converts no_session_persistence true to --no-session-persistence" do
      opts = [no_session_persistence: true]

      args = Command.to_cli_args(opts)
      assert "--no-session-persistence" in args
      refute "true" in args
    end

    test "does not add flag when no_session_persistence is false" do
      opts = [no_session_persistence: false]

      args = Command.to_cli_args(opts)
      refute "--no-session-persistence" in args
    end

    test "converts session_id to --session-id" do
      opts = [session_id: "550e8400-e29b-41d4-a716-446655440000"]

      args = Command.to_cli_args(opts)
      assert "--session-id" in args
      assert "550e8400-e29b-41d4-a716-446655440000" in args
    end

    test "converts fork_session true to --fork-session" do
      opts = [fork_session: true]

      args = Command.to_cli_args(opts)
      assert "--fork-session" in args
      # Boolean flag should not have a value
      refute "true" in args
    end

    test "does not add flag when fork_session is false" do
      opts = [fork_session: false]

      args = Command.to_cli_args(opts)
      refute "--fork-session" in args
    end

    test "combines fork_session with other options" do
      opts = [
        fork_session: true,
        model: "opus",
        max_turns: 10
      ]

      args = Command.to_cli_args(opts)
      assert "--fork-session" in args
      assert "--model" in args
      assert "opus" in args
      assert "--max-turns" in args
      assert "10" in args
    end

    test "does not pass resume as CLI flag (handled separately)" do
      opts = [resume: "session-id-123"]

      args = Command.to_cli_args(opts)
      refute "--resume" in args
      refute "session-id-123" in args
    end

    test "converts continue true to --continue" do
      opts = [continue: true]

      args = Command.to_cli_args(opts)
      assert "--continue" in args
      # Boolean flag should not have a value
      refute "true" in args
    end

    test "does not add flag when continue is false" do
      opts = [continue: false]

      args = Command.to_cli_args(opts)
      refute "--continue" in args
    end

    test "converts max_thinking_tokens to --max-thinking-tokens" do
      opts = [max_thinking_tokens: 10_000]

      args = Command.to_cli_args(opts)
      assert "--max-thinking-tokens" in args
      assert "10000" in args
    end

    test "combines continue with other options" do
      opts = [
        continue: true,
        model: "opus",
        max_turns: 10
      ]

      args = Command.to_cli_args(opts)
      assert "--continue" in args
      assert "--model" in args
      assert "opus" in args
      assert "--max-turns" in args
      assert "10" in args
    end

    test "converts plugins list of paths to multiple --plugin-dir flags" do
      opts = [plugins: ["./my-plugin", "/path/to/plugin"]]

      args = Command.to_cli_args(opts)
      assert "--plugin-dir" in args
      assert "./my-plugin" in args
      assert "/path/to/plugin" in args
      # Should have multiple --plugin-dir flags
      plugin_count = Enum.count(args, &(&1 == "--plugin-dir"))
      assert plugin_count == 2
    end

    test "converts plugins list of maps with atom type to multiple --plugin-dir flags" do
      opts = [plugins: [%{type: :local, path: "./my-plugin"}, %{type: :local, path: "/other"}]]

      args = Command.to_cli_args(opts)
      assert "--plugin-dir" in args
      assert "./my-plugin" in args
      assert "/other" in args
      plugin_count = Enum.count(args, &(&1 == "--plugin-dir"))
      assert plugin_count == 2
    end

    test "converts plugins with atom type" do
      opts = [plugins: [%{type: :local, path: "./my-plugin"}]]

      args = Command.to_cli_args(opts)
      assert "--plugin-dir" in args
      assert "./my-plugin" in args
    end

    test "handles empty plugins list" do
      opts = [plugins: []]

      args = Command.to_cli_args(opts)
      refute "--plugin-dir" in args
    end

    test "handles mixed plugins formats" do
      opts = [plugins: ["./simple-path", %{type: :local, path: "./map-path"}]]

      args = Command.to_cli_args(opts)
      assert "--plugin-dir" in args
      assert "./simple-path" in args
      assert "./map-path" in args
      plugin_count = Enum.count(args, &(&1 == "--plugin-dir"))
      assert plugin_count == 2
    end

    test "converts file list to multiple --file flags" do
      opts = [file: ["file_abc:doc.txt", "file_def:img.png"]]

      args = Command.to_cli_args(opts)
      assert "--file" in args
      assert "file_abc:doc.txt" in args
      assert "file_def:img.png" in args
      file_count = Enum.count(args, &(&1 == "--file"))
      assert file_count == 2
    end

    test "handles empty file list" do
      opts = [file: []]

      args = Command.to_cli_args(opts)
      refute "--file" in args
    end

    test "converts from_pr string to --from-pr" do
      opts = [from_pr: "https://github.com/org/repo/pull/123"]

      args = Command.to_cli_args(opts)
      assert "--from-pr" in args
      assert "https://github.com/org/repo/pull/123" in args
    end

    test "converts from_pr integer to --from-pr" do
      opts = [from_pr: 123]

      args = Command.to_cli_args(opts)
      assert "--from-pr" in args
      assert "123" in args
    end

    test "converts debug true to --debug boolean flag" do
      opts = [debug: true]

      args = Command.to_cli_args(opts)
      assert "--debug" in args
      refute "true" in args
    end

    test "does not add flag when debug is false" do
      opts = [debug: false]

      args = Command.to_cli_args(opts)
      refute "--debug" in args
    end

    test "converts debug string to --debug with filter value" do
      opts = [debug: "api,hooks"]

      args = Command.to_cli_args(opts)
      assert "--debug" in args
      assert "api,hooks" in args
    end

    test "converts debug_file to --debug-file" do
      opts = [debug_file: "/tmp/claude-debug.log"]

      args = Command.to_cli_args(opts)
      assert "--debug-file" in args
      assert "/tmp/claude-debug.log" in args
    end

    test "sandbox merges into settings when only sandbox provided" do
      sandbox = %{"network" => false, "filesystem" => %{"read_only" => true}}
      opts = [sandbox: sandbox]

      args = Command.to_cli_args(opts)
      assert "--settings" in args

      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["sandbox"] == sandbox
    end

    test "sandbox merges into existing settings map" do
      sandbox = %{"network" => false}
      settings = %{"feature" => true, "timeout" => 5000}
      opts = [sandbox: sandbox, settings: settings]

      args = Command.to_cli_args(opts)
      assert "--settings" in args

      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["sandbox"] == sandbox
      assert decoded["feature"] == true
      assert decoded["timeout"] == 5000
    end

    test "sandbox merges into existing settings JSON string" do
      sandbox = %{"network" => false}
      settings = Jason.encode!(%{"feature" => true})
      opts = [sandbox: sandbox, settings: settings]

      args = Command.to_cli_args(opts)
      assert "--settings" in args

      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)

      decoded = Jason.decode!(json_value)
      assert decoded["sandbox"] == sandbox
      assert decoded["feature"] == true
    end

    test "sandbox is not passed as a separate CLI flag" do
      opts = [sandbox: %{"network" => false}]

      args = Command.to_cli_args(opts)
      refute "--sandbox" in args
    end

    test "enable_file_checkpointing is not passed as a CLI flag" do
      opts = [enable_file_checkpointing: true]

      args = Command.to_cli_args(opts)
      refute "--enable-file-checkpointing" in args
      refute "true" in args
    end

    test "enable_file_checkpointing false produces no CLI flag" do
      opts = [enable_file_checkpointing: false]

      args = Command.to_cli_args(opts)
      refute "--enable-file-checkpointing" in args
    end

    test "extra_args are appended at end of CLI args" do
      opts = [model: "opus", extra_args: ["--new-flag", "value"]]

      args = Command.to_cli_args(opts)
      assert "--model" in args
      assert "opus" in args
      assert List.last(args) == "value"
      assert Enum.at(args, -2) == "--new-flag"
    end

    test "empty extra_args produces no extra arguments" do
      opts = [model: "opus", extra_args: []]

      args = Command.to_cli_args(opts)
      assert "--model" in args
      assert "opus" in args
      assert length(args) == 2
    end

    test "extra_args appear after all converted options" do
      opts = [model: "opus", max_turns: 10, extra_args: ["--custom"]]

      args = Command.to_cli_args(opts)
      custom_pos = Enum.find_index(args, &(&1 == "--custom"))
      model_pos = Enum.find_index(args, &(&1 == "--model"))
      turns_pos = Enum.find_index(args, &(&1 == "--max-turns"))

      assert custom_pos > model_pos
      assert custom_pos > turns_pos
    end

    test "max_buffer_size is not passed as a CLI flag" do
      opts = [max_buffer_size: 512]

      args = Command.to_cli_args(opts)
      refute "--max-buffer-size" in args
      refute "512" in args
    end

    test "can_use_tool is not passed as a CLI flag" do
      hook_fn = fn _input, _id -> :allow end
      opts = [can_use_tool: hook_fn]

      args = Command.to_cli_args(opts)
      refute "--can-use-tool" in args
    end

    test "hooks is not passed as a CLI flag" do
      hooks = %{PreToolUse: [%{matcher: "Bash", hooks: [SomeModule]}]}
      opts = [hooks: hooks]

      args = Command.to_cli_args(opts)
      refute "--hooks" in args
    end
  end
end
