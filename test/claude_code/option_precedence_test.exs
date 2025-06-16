defmodule ClaudeCode.OptionPrecedenceTest do
  use ExUnit.Case

  alias ClaudeCode.Options

  setup do
    # Clean up any existing app config
    original_config = Application.get_all_env(:claude_code)

    on_exit(fn ->
      # Restore original config
      for {key, _value} <- Application.get_all_env(:claude_code) do
        Application.delete_env(:claude_code, key)
      end

      for {key, value} <- original_config do
        Application.put_env(:claude_code, key, value)
      end
    end)

    :ok
  end

  describe "option precedence: query > session > app config > defaults" do
    test "query options override session options" do
      session_opts = [
        api_key: "sk-session",
        system_prompt: "Session prompt",
        timeout: 60_000,
        model: "sonnet"
      ]

      query_opts = [
        system_prompt: "Query prompt",
        timeout: 120_000
      ]

      final_opts = Options.resolve_final_options(session_opts, query_opts)

      # Query options should take precedence
      assert final_opts[:system_prompt] == "Query prompt"
      assert final_opts[:timeout] == 120_000

      # Session options preserved where not overridden
      assert final_opts[:api_key] == "sk-session"
      assert final_opts[:model] == "sonnet"
    end

    test "session options override app config" do
      # Set app config
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :timeout, 180_000)

      session_opts = [
        api_key: "sk-session",
        model: "sonnet",
        timeout: 60_000
      ]

      query_opts = []

      final_opts = Options.resolve_final_options(session_opts, query_opts)

      # Session options should override app config
      assert final_opts[:model] == "sonnet"
      assert final_opts[:timeout] == 60_000

      # App config used where not overridden
    end

    test "app config overrides defaults" do
      # Set app config
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :timeout, 180_000)

      session_opts = [api_key: "sk-session"]
      query_opts = []

      final_opts = Options.resolve_final_options(session_opts, query_opts)

      # App config should override defaults
      assert final_opts[:model] == "opus"
      assert final_opts[:timeout] == 180_000
    end

    test "defaults are used when no other options specified" do
      session_opts = [api_key: "sk-session"]
      query_opts = []

      final_opts = Options.resolve_final_options(session_opts, query_opts)

      # Should use schema defaults
      # No model default - CLI handles its own defaults
      refute Keyword.has_key?(final_opts, :model)
      assert final_opts[:timeout] == 300_000
    end

    test "complete precedence chain" do
      # Set app config (level 3)
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :timeout, 180_000)
      Application.put_env(:claude_code, :max_turns, 100)

      # Session options (level 2) - override some app config
      session_opts = [
        api_key: "sk-session",
        model: "sonnet",
        timeout: 60_000,
        system_prompt: "Session prompt",
        allowed_tools: ["View", "GrepTool"]
      ]

      # Query options (level 1) - override some session options
      query_opts = [
        system_prompt: "Query prompt",
        timeout: 30_000,
        allowed_tools: ["BatchTool"]
      ]

      final_opts = Options.resolve_final_options(session_opts, query_opts)

      # Query options (highest precedence)
      assert final_opts[:system_prompt] == "Query prompt"
      assert final_opts[:timeout] == 30_000
      assert final_opts[:allowed_tools] == ["BatchTool"]

      # Session options (override app config)
      assert final_opts[:model] == "sonnet"
      assert final_opts[:api_key] == "sk-session"

      # App config (override defaults)
      assert final_opts[:max_turns] == 100
    end
  end

  describe "apply_app_config_defaults/1" do
    test "applies app config to session options" do
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :timeout, 180_000)

      session_opts = [api_key: "sk-test"]

      opts_with_config = Options.apply_app_config_defaults(session_opts)

      assert opts_with_config[:model] == "opus"
      assert opts_with_config[:timeout] == 180_000
      assert opts_with_config[:api_key] == "sk-test"
    end

    test "session options take precedence over app config" do
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :timeout, 180_000)

      session_opts = [
        api_key: "sk-test",
        model: "sonnet",
        system_prompt: "Custom prompt"
      ]

      opts_with_config = Options.apply_app_config_defaults(session_opts)

      # Session options preserved
      assert opts_with_config[:model] == "sonnet"
      assert opts_with_config[:system_prompt] == "Custom prompt"

      # App config applied where not specified
      assert opts_with_config[:timeout] == 180_000
    end

    test "handles empty app config gracefully" do
      session_opts = [api_key: "sk-test", model: "sonnet"]

      opts_with_config = Options.apply_app_config_defaults(session_opts)

      # Should return original options unchanged
      assert opts_with_config == session_opts
    end
  end

  describe "app config mapping" do
    test "maps app config keys to option keys correctly" do
      Application.put_env(:claude_code, :model, "opus")
      Application.put_env(:claude_code, :system_prompt, "App prompt")
      Application.put_env(:claude_code, :timeout, 180_000)

      config = Options.get_app_config()

      assert config[:model] == "opus"
      assert config[:system_prompt] == "App prompt"
      assert config[:timeout] == 180_000
    end

    test "ignores unknown app config keys" do
      Application.put_env(:claude_code, :unknown_option, "value")
      Application.put_env(:claude_code, :model, "opus")

      config = Options.get_app_config()

      assert config[:model] == "opus"
      refute Keyword.has_key?(config, :unknown_option)
    end
  end
end
