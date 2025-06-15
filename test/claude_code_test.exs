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

    test "requires api_key option" do
      assert_raise ArgumentError, ~r/required :api_key option not found/, fn ->
        ClaudeCode.start_link([])
      end
    end

    test "accepts flattened options directly" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          model: "opus",
          system_prompt: "You are an Elixir expert",
          allowed_tools: ["Bash(git:*)", "View", "GlobTool"],
          max_conversation_turns: 20,
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

    test "accepts max_conversation_turns option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          max_conversation_turns: 10
        )

      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "accepts working_directory option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          working_directory: "/tmp"
        )

      assert is_pid(session)
      ClaudeCode.stop(session)
    end

    test "accepts permission_mode option" do
      {:ok, session} =
        ClaudeCode.start_link(
          api_key: "test-key",
          permission_mode: :auto_accept_reads
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

      # Invalid permission_mode
      assert_raise ArgumentError, fn ->
        ClaudeCode.start_link(
          api_key: "test-key",
          permission_mode: :invalid_mode
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
end
