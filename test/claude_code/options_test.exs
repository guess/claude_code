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

    test "validates cli_path with :bundled atom" do
      assert {:ok, validated} = Options.validate_session_options(cli_path: :bundled)
      assert validated[:cli_path] == :bundled
    end

    test "validates cli_path with :global atom" do
      assert {:ok, validated} = Options.validate_session_options(cli_path: :global)
      assert validated[:cli_path] == :global
    end

    test "validates cli_path with string path" do
      assert {:ok, validated} = Options.validate_session_options(cli_path: "/usr/bin/claude")
      assert validated[:cli_path] == "/usr/bin/claude"
    end

    test "rejects invalid cli_path atom" do
      assert {:error, _} = Options.validate_session_options(cli_path: :invalid)
    end

    test "validates strict_mcp_config option" do
      opts = [strict_mcp_config: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:strict_mcp_config] == true

      opts = [strict_mcp_config: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:strict_mcp_config] == false
    end

    test "defaults strict_mcp_config to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:strict_mcp_config] == false
    end

    test "validates allow_dangerously_skip_permissions option" do
      opts = [allow_dangerously_skip_permissions: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:allow_dangerously_skip_permissions] == true

      opts = [allow_dangerously_skip_permissions: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:allow_dangerously_skip_permissions] == false
    end

    test "defaults allow_dangerously_skip_permissions to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:allow_dangerously_skip_permissions] == false
    end

    test "validates disable_slash_commands option" do
      opts = [disable_slash_commands: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:disable_slash_commands] == true

      opts = [disable_slash_commands: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:disable_slash_commands] == false
    end

    test "defaults disable_slash_commands to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:disable_slash_commands] == false
    end

    test "validates no_session_persistence option" do
      opts = [no_session_persistence: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:no_session_persistence] == true

      opts = [no_session_persistence: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:no_session_persistence] == false
    end

    test "defaults no_session_persistence to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:no_session_persistence] == false
    end

    test "validates session_id option" do
      opts = [session_id: "550e8400-e29b-41d4-a716-446655440000"]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:session_id] == "550e8400-e29b-41d4-a716-446655440000"
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

    test "validates output_format option" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      opts = [output_format: %{type: :json_schema, schema: schema}]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:output_format] == %{type: :json_schema, schema: schema}
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

    test "validates fork_session option" do
      opts = [fork_session: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:fork_session] == true

      opts = [fork_session: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:fork_session] == false
    end

    test "defaults fork_session to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:fork_session] == false
    end

    test "validates resume and fork_session together" do
      opts = [resume: "session-id-123", fork_session: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:resume] == "session-id-123"
      assert validated[:fork_session] == true
    end

    test "validates continue option" do
      opts = [continue: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:continue] == true

      opts = [continue: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:continue] == false
    end

    test "defaults continue to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:continue] == false
    end

    test "validates max_thinking_tokens option" do
      opts = [max_thinking_tokens: 10_000]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:max_thinking_tokens] == 10_000
    end

    test "validates plugins option as list of paths" do
      opts = [plugins: ["./my-plugin", "/path/to/plugin"]]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:plugins] == ["./my-plugin", "/path/to/plugin"]
    end

    test "validates plugins option as list of maps with atom type" do
      opts = [plugins: [%{type: :local, path: "./my-plugin"}]]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:plugins] == [%{type: :local, path: "./my-plugin"}]
    end

    test "validates plugins option with mixed formats" do
      opts = [plugins: ["./simple-plugin", %{type: :local, path: "./map-plugin"}]]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:plugins] == ["./simple-plugin", %{type: :local, path: "./map-plugin"}]
    end

    test "validates sandbox option as a map" do
      opts = [sandbox: %{"network" => false, "filesystem" => %{"read_only" => true}}]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:sandbox] == %{"network" => false, "filesystem" => %{"read_only" => true}}
    end

    test "sandbox is not set by default" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      refute Keyword.has_key?(validated, :sandbox)
    end

    test "validates enable_file_checkpointing option" do
      opts = [enable_file_checkpointing: true]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:enable_file_checkpointing] == true

      opts = [enable_file_checkpointing: false]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:enable_file_checkpointing] == false
    end

    test "defaults enable_file_checkpointing to false" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:enable_file_checkpointing] == false
    end

    test "validates extra_args option as list of strings" do
      opts = [extra_args: ["--some-flag", "value"]]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:extra_args] == ["--some-flag", "value"]
    end

    test "defaults extra_args to empty list" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:extra_args] == []
    end

    test "validates max_buffer_size option" do
      opts = [max_buffer_size: 512]
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:max_buffer_size] == 512
    end

    test "defaults max_buffer_size to 1MB" do
      opts = []
      assert {:ok, validated} = Options.validate_session_options(opts)
      assert validated[:max_buffer_size] == 1_048_576
    end

    test "rejects zero max_buffer_size" do
      assert {:error, _} = Options.validate_session_options(max_buffer_size: 0)
    end
  end

  describe "can_use_tool validation" do
    test "accepts a module atom" do
      {:ok, opts} = Options.validate_session_options(can_use_tool: SomeModule)
      assert Keyword.get(opts, :can_use_tool) == SomeModule
    end

    test "accepts a 2-arity function" do
      hook_fn = fn _input, _id -> :allow end
      {:ok, opts} = Options.validate_session_options(can_use_tool: hook_fn)
      assert is_function(Keyword.get(opts, :can_use_tool), 2)
    end

    test "rejects non-module non-function values" do
      assert {:error, _} = Options.validate_session_options(can_use_tool: "not valid")
    end

    test "cannot be used with permission_prompt_tool" do
      hook_fn = fn _input, _id -> :allow end

      assert_raise ArgumentError, ~r/cannot.*both/i, fn ->
        Options.validate_session_options(
          can_use_tool: hook_fn,
          permission_prompt_tool: "stdio"
        )
      end
    end
  end

  describe "hooks validation" do
    test "accepts a map with atom keys and matcher lists" do
      hooks = %{
        PreToolUse: [%{matcher: "Bash", hooks: [SomeModule]}]
      }

      {:ok, opts} = Options.validate_session_options(hooks: hooks)
      assert is_map(Keyword.get(opts, :hooks))
    end

    test "accepts a map with function hooks" do
      hooks = %{
        PostToolUse: [%{hooks: [fn _input, _id -> :ok end]}]
      }

      {:ok, opts} = Options.validate_session_options(hooks: hooks)
      assert is_map(Keyword.get(opts, :hooks))
    end

    test "rejects non-map values" do
      assert {:error, _} = Options.validate_session_options(hooks: "not a map")
    end
  end

  describe "validate_query_options/1" do
    test "validates valid options" do
      opts = [
        system_prompt: "Focus on performance",
        timeout: 120_000,
        allowed_tools: ["Bash(git:*)"],
        permission_mode: :bypass_permissions,
        add_dir: ["/home/user/docs"]
      ]

      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:system_prompt] == "Focus on performance"
      assert validated[:timeout] == 120_000
      assert validated[:allowed_tools] == ["Bash(git:*)"]
      assert validated[:permission_mode] == :bypass_permissions
      assert validated[:add_dir] == ["/home/user/docs"]
    end

    test "accepts empty options" do
      assert {:ok, validated} = Options.validate_query_options([])
      # Only defaults present
      assert validated[:extra_args] == []
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

    test "validates output_format in query options" do
      schema = %{"type" => "object", "properties" => %{"result" => %{"type" => "number"}}}
      opts = [output_format: %{type: :json_schema, schema: schema}]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:output_format] == %{type: :json_schema, schema: schema}
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

    test "validates max_thinking_tokens in query options" do
      opts = [max_thinking_tokens: 5000]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:max_thinking_tokens] == 5000
    end

    test "validates plugins in query options" do
      opts = [plugins: ["./my-plugin"]]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:plugins] == ["./my-plugin"]
    end

    test "validates extra_args in query options" do
      opts = [extra_args: ["--new-flag"]]
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:extra_args] == ["--new-flag"]
    end

    test "defaults extra_args to empty list in query options" do
      opts = []
      assert {:ok, validated} = Options.validate_query_options(opts)
      assert validated[:extra_args] == []
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
