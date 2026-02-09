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
      args = Command.to_cli_args(system_prompt: "You are helpful")

      assert "--system-prompt" in args
      assert "You are helpful" in args
    end

    test "converts allowed_tools to --allowedTools CSV" do
      args = Command.to_cli_args(allowed_tools: ["View", "GlobTool", "Bash(git:*)"])

      assert "--allowedTools" in args
      assert "View,GlobTool,Bash(git:*)" in args
    end

    test "converts max_turns to --max-turns" do
      args = Command.to_cli_args(max_turns: 20)

      assert "--max-turns" in args
      assert "20" in args
    end

    test "converts model to --model" do
      args = Command.to_cli_args(model: "opus")

      assert "--model" in args
      assert "opus" in args
    end

    test "converts fallback_model to --fallback-model" do
      args = Command.to_cli_args(fallback_model: "sonnet")

      assert "--fallback-model" in args
      assert "sonnet" in args
    end

    test "converts permission_mode atoms to CLI values" do
      assert "acceptEdits" in Command.to_cli_args(permission_mode: :accept_edits)
      assert "bypassPermissions" in Command.to_cli_args(permission_mode: :bypass_permissions)
      assert "delegate" in Command.to_cli_args(permission_mode: :delegate)
      assert "dontAsk" in Command.to_cli_args(permission_mode: :dont_ask)
      assert "plan" in Command.to_cli_args(permission_mode: :plan)
      assert "default" in Command.to_cli_args(permission_mode: :default)
    end

    test "converts add_dir to multiple --add-dir flags" do
      args = Command.to_cli_args(add_dir: ["/tmp", "/var/log"])

      assert "--add-dir" in args
      assert "/tmp" in args
      assert "/var/log" in args
      assert Enum.count(args, &(&1 == "--add-dir")) == 2
    end

    test "handles empty add_dir list" do
      args = Command.to_cli_args(add_dir: [])

      refute "--add-dir" in args
    end

    test "converts boolean flags without values" do
      assert "--fork-session" in Command.to_cli_args(fork_session: true)
      refute "--fork-session" in Command.to_cli_args(fork_session: false)

      assert "--continue" in Command.to_cli_args(continue: true)
      refute "--continue" in Command.to_cli_args(continue: false)

      assert "--include-partial-messages" in Command.to_cli_args(include_partial_messages: true)
      refute "--include-partial-messages" in Command.to_cli_args(include_partial_messages: false)

      assert "--strict-mcp-config" in Command.to_cli_args(strict_mcp_config: true)
      refute "--strict-mcp-config" in Command.to_cli_args(strict_mcp_config: false)

      assert "--no-session-persistence" in Command.to_cli_args(no_session_persistence: true)
      refute "--no-session-persistence" in Command.to_cli_args(no_session_persistence: false)

      assert "--disable-slash-commands" in Command.to_cli_args(disable_slash_commands: true)
      refute "--disable-slash-commands" in Command.to_cli_args(disable_slash_commands: false)

      assert "--allow-dangerously-skip-permissions" in Command.to_cli_args(allow_dangerously_skip_permissions: true)
      refute "--allow-dangerously-skip-permissions" in Command.to_cli_args(allow_dangerously_skip_permissions: false)
    end

    test "ignores nil values" do
      args = Command.to_cli_args(system_prompt: nil, model: "opus")

      refute "--system-prompt" in args
      assert "--model" in args
    end

    test "ignores internal-only options" do
      args = Command.to_cli_args(api_key: "sk-test", name: :session, timeout: 60_000, cli_path: :bundled)

      refute "--api-key" in args
      refute "--name" in args
      refute "--timeout" in args
      refute "--cli-path" in args
    end

    test "converts output_format with json_schema" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      args = Command.to_cli_args(output_format: %{type: :json_schema, schema: schema})

      assert "--json-schema" in args

      schema_index = Enum.find_index(args, &(&1 == "--json-schema"))
      json_value = Enum.at(args, schema_index + 1)
      decoded = Jason.decode!(json_value)
      assert decoded["type"] == "object"
    end

    test "converts settings map to JSON" do
      args = Command.to_cli_args(settings: %{"feature" => true})

      assert "--settings" in args
      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)
      decoded = Jason.decode!(json_value)
      assert decoded["feature"] == true
    end

    test "converts settings string as-is" do
      args = Command.to_cli_args(settings: "/path/to/settings.json")

      assert "--settings" in args
      assert "/path/to/settings.json" in args
    end

    test "sandbox merges into settings" do
      sandbox = %{"network" => false}
      args = Command.to_cli_args(sandbox: sandbox)

      assert "--settings" in args
      refute "--sandbox" in args

      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)
      decoded = Jason.decode!(json_value)
      assert decoded["sandbox"] == sandbox
    end

    test "sandbox merges into existing settings map" do
      sandbox = %{"network" => false}
      settings = %{"feature" => true}
      args = Command.to_cli_args(sandbox: sandbox, settings: settings)

      settings_index = Enum.find_index(args, &(&1 == "--settings"))
      json_value = Enum.at(args, settings_index + 1)
      decoded = Jason.decode!(json_value)
      assert decoded["sandbox"] == sandbox
      assert decoded["feature"] == true
    end

    test "converts mcp_servers with module atoms" do
      args = Command.to_cli_args(mcp_servers: %{"my-tools" => MyApp.MCPServer})

      assert "--mcp-config" in args
      mcp_index = Enum.find_index(args, &(&1 == "--mcp-config"))
      json_value = Enum.at(args, mcp_index + 1)
      decoded = Jason.decode!(json_value)
      assert decoded["mcpServers"]["my-tools"]["command"] == "mix"
    end

    test "converts betas to multiple --betas flags" do
      args = Command.to_cli_args(betas: ["feature-x", "feature-y"])

      assert Enum.count(args, &(&1 == "--betas")) == 2
      assert "feature-x" in args
      assert "feature-y" in args
    end

    test "handles empty betas list" do
      args = Command.to_cli_args(betas: [])

      refute "--betas" in args
    end

    test "converts plugins to --plugin-dir flags" do
      args = Command.to_cli_args(plugins: ["./my-plugin", %{type: :local, path: "/other"}])

      assert Enum.count(args, &(&1 == "--plugin-dir")) == 2
      assert "./my-plugin" in args
      assert "/other" in args
    end

    test "handles empty plugins list" do
      args = Command.to_cli_args(plugins: [])

      refute "--plugin-dir" in args
    end

    test "converts file list to multiple --file flags" do
      args = Command.to_cli_args(file: ["file_abc:doc.txt", "file_def:img.png"])

      assert Enum.count(args, &(&1 == "--file")) == 2
      assert "file_abc:doc.txt" in args
      assert "file_def:img.png" in args
    end

    test "converts from_pr to --from-pr" do
      args = Command.to_cli_args(from_pr: 123)

      assert "--from-pr" in args
      assert "123" in args
    end

    test "converts debug boolean to --debug flag" do
      assert "--debug" in Command.to_cli_args(debug: true)
      refute "--debug" in Command.to_cli_args(debug: false)
    end

    test "converts debug string to --debug with value" do
      args = Command.to_cli_args(debug: "api,hooks")

      assert "--debug" in args
      assert "api,hooks" in args
    end

    test "converts debug_file to --debug-file" do
      args = Command.to_cli_args(debug_file: "/tmp/debug.log")

      assert "--debug-file" in args
      assert "/tmp/debug.log" in args
    end

    test "does not pass resume as CLI flag" do
      args = Command.to_cli_args(resume: "session-id-123")

      refute "--resume" in args
    end

    test "cwd is not converted to a CLI flag" do
      args = Command.to_cli_args(cwd: "/tmp")

      refute "--cwd" in args
    end

    test "enable_file_checkpointing is not converted to a CLI flag" do
      args = Command.to_cli_args(enable_file_checkpointing: true)

      refute "--enable-file-checkpointing" in args
    end
  end
end
