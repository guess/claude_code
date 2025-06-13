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
      Process.flag(:trap_exit, true)
      {:error, _} = ClaudeCode.start_link([])
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
