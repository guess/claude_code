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
