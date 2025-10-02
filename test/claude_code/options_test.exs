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

    test "rejects missing required api_key when environment variable not set" do
      original_env = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")

      try do
        opts = [model: "opus"]
        assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_session_options(opts)
      after
        if original_env, do: System.put_env("ANTHROPIC_API_KEY", original_env)
      end
    end

    test "uses ANTHROPIC_API_KEY environment variable as fallback" do
      original_env = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "env-test-key")

      try do
        opts = [model: "opus"]
        assert {:ok, validated} = Options.validate_session_options(opts)
        assert validated[:api_key] == "env-test-key"
        assert validated[:model] == "opus"
      after
        if original_env do
          System.put_env("ANTHROPIC_API_KEY", original_env)
        else
          System.delete_env("ANTHROPIC_API_KEY")
        end
      end
    end

    test "explicit api_key takes precedence over environment variable" do
      original_env = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "env-test-key")

      try do
        opts = [api_key: "explicit-key", model: "opus"]
        assert {:ok, validated} = Options.validate_session_options(opts)
        assert validated[:api_key] == "explicit-key"
        assert validated[:model] == "opus"
      after
        if original_env do
          System.put_env("ANTHROPIC_API_KEY", original_env)
        else
          System.delete_env("ANTHROPIC_API_KEY")
        end
      end
    end

    test "rejects invalid timeout type" do
      opts = [api_key: "sk-ant-test", timeout: "not_a_number"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_session_options(opts)
    end

    test "rejects unknown options" do
      opts = [api_key: "sk-ant-test", unknown_option: "value"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_session_options(opts)
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

    test "rejects invalid options" do
      opts = [invalid_option: "value"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_query_options(opts)
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

    test "ignores internal options (api_key, name, timeout, permission_handler)" do
      opts = [api_key: "sk-ant-test", name: :session, timeout: 60_000, permission_handler: :custom, model: "opus"]

      args = Options.to_cli_args(opts)
      refute "--api-key" in args
      refute "--name" in args
      refute "--timeout" in args
      refute "--permission-handler" in args
      refute "sk-ant-test" in args
      refute ":session" in args
      refute "60000" in args
      refute ":custom" in args
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
    test "uses environment variable when no app config or session opts" do
      # Clear app config
      original_config = Application.get_all_env(:claude_code)
      Application.delete_env(:claude_code, :api_key)

      # Set environment variable
      original_env = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "env-fallback-key")

      try do
        result = Options.apply_app_config_defaults([])
        assert result[:api_key] == "env-fallback-key"
      after
        # Restore original config and environment
        for {key, value} <- original_config do
          Application.put_env(:claude_code, key, value)
        end

        if original_env do
          System.put_env("ANTHROPIC_API_KEY", original_env)
        else
          System.delete_env("ANTHROPIC_API_KEY")
        end
      end
    end
  end
end
