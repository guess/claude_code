defmodule ClaudeCodeTest do
  use ExUnit.Case

  doctest ClaudeCode

  describe "start_link/1" do
    test "starts a session with valid API key" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      assert is_pid(session)
      assert ClaudeCode.alive?(session)
      ClaudeCode.stop(session)
    end

    test "starts a named session" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          name: :test_session
        )

      assert ClaudeCode.alive?(:test_session)
      assert Process.whereis(:test_session) == session

      ClaudeCode.stop(:test_session)
    end

    test "can start without api_key - CLI handles environment fallback" do
      # This should succeed - the CLI will check for ANTHROPIC_API_KEY itself
      {:ok, session} = ClaudeCode.start_link()
      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "works without api_key when provided in app config" do
      # Set application config
      original_config = Application.get_all_env(:claude_code)
      Application.put_env(:claude_code, :api_key, "app-config-key")

      try do
        {:ok, session} = ClaudeCode.start_link()
        assert is_pid(session)
        assert ClaudeCode.alive?(session)
        ClaudeCode.stop(session)
      after
        # Restore original config
        Application.delete_env(:claude_code, :api_key)

        for {key, value} <- original_config do
          Application.put_env(:claude_code, key, value)
        end
      end
    end

    test "session api_key overrides app config" do
      # Set application config
      original_config = Application.get_all_env(:claude_code)
      Application.put_env(:claude_code, :api_key, "app-config-key")

      try do
        {:ok, session} = ClaudeCode.start_link(api_key: "session-key")
        assert is_pid(session)
        assert ClaudeCode.alive?(session)
        ClaudeCode.stop(session)
      after
        # Restore original config
        Application.delete_env(:claude_code, :api_key)

        for {key, value} <- original_config do
          Application.put_env(:claude_code, key, value)
        end
      end
    end

    test "accepts flattened options directly" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          model: "opus",
          system_prompt: "You are an Elixir expert",
          allowed_tools: ["Bash(git:*)", "View", "GlobTool"],
          max_turns: 20,
          timeout: 60_000
        )

      assert is_pid(session)
      assert ClaudeCode.alive?(session)
      ClaudeCode.stop(session)
    end

    test "accepts system_prompt option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          system_prompt: "You are a helpful assistant"
        )

      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "accepts allowed_tools option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          allowed_tools: ["View", "GlobTool", "Bash(git:*)"]
        )

      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "accepts max_turns option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          max_turns: 10
        )

      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "accepts cwd option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          cwd: "/tmp"
        )

      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "accepts timeout option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          timeout: 120_000
        )

      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "rejects unknown options" do
      Process.flag(:trap_exit, true)

      assert_raise ArgumentError, fn ->
        ClaudeCode.start_link(
          api_key: "test-key",
          invalid_option: "value"
        )
      end
    end

    test "validates option types" do
      Process.flag(:trap_exit, true)

      # Invalid timeout type
      assert_raise ArgumentError, fn ->
        ClaudeCode.start_link(
          api_key: "test-key",
          timeout: "not_a_number"
        )
      end

      # Invalid allowed_tools type
      assert_raise ArgumentError, fn ->
        ClaudeCode.start_link(
          api_key: "test-key",
          allowed_tools: "not_a_list"
        )
      end

      # Invalid allowed_tools content (should be strings, not atoms)
      assert_raise ArgumentError, fn ->
        ClaudeCode.start_link(
          api_key: "test-key",
          allowed_tools: [:read, :write]
        )
      end
    end
  end

  describe "alive?/1" do
    test "returns true for running session" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      assert ClaudeCode.alive?(session)
      ClaudeCode.stop(session)
    end

    test "returns false for stopped session" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      ClaudeCode.stop(session)

      # Give it a moment to stop
      Process.sleep(100)

      refute ClaudeCode.alive?(session)
    end

    test "returns false for non-existent named session" do
      refute ClaudeCode.alive?(:non_existent_session)
    end
  end

  describe "stop/1" do
    test "stops a running session" do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")
      assert :ok = ClaudeCode.stop(session)

      # Give it a moment to stop
      Process.sleep(100)

      refute Process.alive?(session)
    end
  end

  describe "health/1" do
    test "returns health status from adapter" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [ClaudeCode.Test.result("ok")]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, ClaudeCode})

      assert :healthy = ClaudeCode.health(session)

      ClaudeCode.stop(session)
    end
  end
end
