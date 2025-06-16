defmodule ClaudeCode.OptionsTest do
  use ExUnit.Case

  alias ClaudeCode.Options

  describe "session_schema/0" do
    test "returns session options schema" do
      schema = Options.session_schema()

      assert is_list(schema)
      assert Keyword.has_key?(schema, :api_key)
      assert Keyword.has_key?(schema, :model)
      assert Keyword.has_key?(schema, :system_prompt)
      assert Keyword.has_key?(schema, :allowed_tools)
      assert Keyword.has_key?(schema, :max_turns)
      assert Keyword.has_key?(schema, :cwd)
      assert Keyword.has_key?(schema, :timeout)
      assert Keyword.has_key?(schema, :permission_handler)
      assert Keyword.has_key?(schema, :name)
      assert Keyword.has_key?(schema, :dangerously_skip_permissions)
      assert Keyword.has_key?(schema, :add_dir)
    end

    test "api_key is required" do
      schema = Options.session_schema()
      api_key_opts = Keyword.get(schema, :api_key)

      assert Keyword.get(api_key_opts, :required) == true
      assert Keyword.get(api_key_opts, :type) == :string
    end

    test "model has proper type" do
      schema = Options.session_schema()
      model_opts = Keyword.get(schema, :model)

      assert Keyword.get(model_opts, :type) == :string
      # No default value - let CLI handle its own defaults
      refute Keyword.has_key?(model_opts, :default)
    end

    test "timeout has proper type and default" do
      schema = Options.session_schema()
      timeout_opts = Keyword.get(schema, :timeout)

      assert Keyword.get(timeout_opts, :type) == :timeout
      assert Keyword.get(timeout_opts, :default) == 300_000
    end

    test "dangerously_skip_permissions has proper type and default" do
      schema = Options.session_schema()
      skip_perms_opts = Keyword.get(schema, :dangerously_skip_permissions)

      assert Keyword.get(skip_perms_opts, :type) == :boolean
      assert Keyword.get(skip_perms_opts, :default) == false
    end

    test "add_dir has proper type" do
      schema = Options.session_schema()
      add_dir_opts = Keyword.get(schema, :add_dir)

      assert Keyword.get(add_dir_opts, :type) == {:list, :string}
      # No default value
      refute Keyword.has_key?(add_dir_opts, :default)
    end
  end

  describe "query_schema/0" do
    test "returns query options schema" do
      schema = Options.query_schema()

      assert is_list(schema)
      assert Keyword.has_key?(schema, :system_prompt)
      assert Keyword.has_key?(schema, :timeout)
      assert Keyword.has_key?(schema, :allowed_tools)
      assert Keyword.has_key?(schema, :dangerously_skip_permissions)
      assert Keyword.has_key?(schema, :add_dir)
    end

    test "query options are all optional" do
      schema = Options.query_schema()

      for {_key, opts} <- schema do
        refute Keyword.get(opts, :required, false)
      end
    end
  end

  describe "validate_session_options/1" do
    test "validates valid options" do
      opts = [
        api_key: "sk-ant-test",
        model: "opus",
        system_prompt: "You are helpful",
        allowed_tools: ["View", "GlobTool", "Bash(git:*)"],
        max_turns: 20,
        timeout: 60_000,
        dangerously_skip_permissions: true,
        add_dir: ["/tmp", "/var/log"]
      ]

      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:api_key] == "sk-ant-test"
      assert validated[:model] == "opus"
      assert validated[:timeout] == 60_000
      assert validated[:dangerously_skip_permissions] == true
      assert validated[:add_dir] == ["/tmp", "/var/log"]
    end

    test "applies default values" do
      opts = [api_key: "sk-ant-test"]

      assert {:ok, validated} = Options.validate_session_options(opts)
      # No model default - CLI handles its own defaults
      refute Keyword.has_key?(validated, :model)
      assert validated[:timeout] == 300_000
      assert validated[:dangerously_skip_permissions] == false
    end

    test "rejects missing required api_key" do
      opts = [model: "opus"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_session_options(opts)
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
        dangerously_skip_permissions: true,
        add_dir: ["/home/user/docs"]
      ]

      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:system_prompt] == "Focus on performance"
      assert validated[:timeout] == 120_000
      assert validated[:allowed_tools] == ["Bash(git:*)"]
      assert validated[:dangerously_skip_permissions] == true
      assert validated[:add_dir] == ["/home/user/docs"]
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

    test "converts allowed_tools to --allowed-tools" do
      opts = [allowed_tools: ["View", "GlobTool", "Bash(git:*)"]]

      args = Options.to_cli_args(opts)
      assert "--allowed-tools" in args
      assert "View,GlobTool,Bash(git:*)" in args
    end

    test "converts max_turns to --max-turns" do
      opts = [max_turns: 20]

      args = Options.to_cli_args(opts)
      assert "--max-turns" in args
      assert "20" in args
    end

    test "converts cwd to --cwd" do
      opts = [cwd: "/tmp"]

      args = Options.to_cli_args(opts)
      assert "--cwd" in args
      assert "/tmp" in args
    end

    test "converts timeout to --timeout" do
      opts = [timeout: 120_000]

      args = Options.to_cli_args(opts)
      assert "--timeout" in args
      assert "120000" in args
    end

    test "ignores api_key and name options" do
      opts = [api_key: "sk-ant-test", name: :session, model: "opus"]

      args = Options.to_cli_args(opts)
      refute "--api-key" in args
      refute "--name" in args
      refute "sk-ant-test" in args
      refute ":session" in args
    end

    test "ignores nil values" do
      opts = [system_prompt: nil, model: "opus"]

      args = Options.to_cli_args(opts)
      refute "--system-prompt" in args
      refute nil in args
    end

    test "converts dangerously_skip_permissions to --dangerously-skip-permissions when true" do
      opts = [dangerously_skip_permissions: true]

      args = Options.to_cli_args(opts)
      assert "--dangerously-skip-permissions" in args
      # Should not have a separate value argument
      refute "true" in args
    end

    test "ignores dangerously_skip_permissions when false" do
      opts = [dangerously_skip_permissions: false]

      args = Options.to_cli_args(opts)
      refute "--dangerously-skip-permissions" in args
      refute "false" in args
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
end
