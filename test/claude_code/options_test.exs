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
      assert Keyword.has_key?(schema, :permission_mode)
      assert Keyword.has_key?(schema, :timeout)
      assert Keyword.has_key?(schema, :permission_handler)
      assert Keyword.has_key?(schema, :name)
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

    test "permission_mode has valid enum values" do
      schema = Options.session_schema()
      permission_opts = Keyword.get(schema, :permission_mode)

      assert Keyword.get(permission_opts, :type) == {:in, [:auto_accept_all, :auto_accept_reads, :ask_always]}
      assert Keyword.get(permission_opts, :default) == :ask_always
    end

    test "timeout has proper type and default" do
      schema = Options.session_schema()
      timeout_opts = Keyword.get(schema, :timeout)

      assert Keyword.get(timeout_opts, :type) == :timeout
      assert Keyword.get(timeout_opts, :default) == 300_000
    end
  end

  describe "query_schema/0" do
    test "returns query options schema" do
      schema = Options.query_schema()

      assert is_list(schema)
      assert Keyword.has_key?(schema, :system_prompt)
      assert Keyword.has_key?(schema, :timeout)
      assert Keyword.has_key?(schema, :allowed_tools)
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
        permission_mode: :auto_accept_reads,
        timeout: 60_000
      ]

      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:api_key] == "sk-ant-test"
      assert validated[:model] == "opus"
      assert validated[:timeout] == 60_000
    end

    test "applies default values" do
      opts = [api_key: "sk-ant-test"]

      assert {:ok, validated} = Options.validate_session_options(opts)
      # No model default - CLI handles its own defaults
      refute Keyword.has_key?(validated, :model)
      assert validated[:permission_mode] == :ask_always
      assert validated[:timeout] == 300_000
    end

    test "rejects missing required api_key" do
      opts = [model: "opus"]

      assert {:error, %NimbleOptions.ValidationError{}} = Options.validate_session_options(opts)
    end

    test "rejects invalid permission_mode" do
      opts = [api_key: "sk-ant-test", permission_mode: :invalid]

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
        allowed_tools: ["Bash(git:*)"]
      ]

      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:system_prompt] == "Focus on performance"
      assert validated[:timeout] == 120_000
      assert validated[:allowed_tools] == ["Bash(git:*)"]
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

    test "converts permission_mode to --permission-mode" do
      opts = [permission_mode: :auto_accept_reads]

      args = Options.to_cli_args(opts)
      assert "--permission-mode" in args
      assert "auto-accept-reads" in args
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
  end

  describe "merge_options/2" do
    test "merges session and query options with query taking precedence" do
      session_opts = [
        system_prompt: "You are helpful",
        timeout: 60_000,
        allowed_tools: ["View", "GlobTool"]
      ]

      query_opts = [
        system_prompt: "Focus on performance",
        timeout: 120_000
      ]

      merged = Options.merge_options(session_opts, query_opts)

      assert merged[:system_prompt] == "Focus on performance"
      assert merged[:timeout] == 120_000
      assert merged[:allowed_tools] == ["View", "GlobTool"]
    end

    test "preserves session options when query options are empty" do
      session_opts = [
        system_prompt: "You are helpful",
        timeout: 60_000
      ]

      query_opts = []

      merged = Options.merge_options(session_opts, query_opts)

      assert merged[:system_prompt] == "You are helpful"
      assert merged[:timeout] == 60_000
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
