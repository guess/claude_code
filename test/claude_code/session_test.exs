defmodule ClaudeCode.SessionTest do
  use ExUnit.Case

  alias ClaudeCode.Session

  describe "start_link/1" do
    test "starts with required options" do
      {:ok, pid} = Session.start_link(api_key: "test-key")
      assert is_pid(pid)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom model" do
      {:ok, pid} =
        Session.start_link(
          api_key: "test-key",
          model: "claude-3-opus-20240229"
        )

      state = :sys.get_state(pid)
      assert state.model == "claude-3-opus-20240229"

      GenServer.stop(pid)
    end

    test "starts with name" do
      {:ok, pid} =
        Session.start_link(
          api_key: "test-key",
          name: :test_session
        )

      assert Process.whereis(:test_session) == pid
      GenServer.stop(pid)
    end
  end

  describe "query handling with mock CLI" do
    setup do
      # Create a mock CLI script that outputs test responses
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Write a simple mock script that echoes JSON matching real CLI format
      File.write!(mock_script, """
      #!/bin/bash
      # Output system init message
      echo '{"type":"system","subtype":"init","session_id":"test-123"}'
      # Output assistant message
      echo '{"type":"assistant","message":{"content":[{"text":"Hello from mock CLI!","type":"text"}]}}'
      # Output result message
      echo '{"type":"result","subtype":"success","result":"Hello from mock CLI!","session_id":"test-123"}'
      exit 0
      """)

      File.chmod!(mock_script, 0o755)

      # Add mock directory to PATH
      original_path = System.get_env("PATH")
      System.put_env("PATH", "#{mock_dir}:#{original_path}")

      on_exit(fn ->
        System.put_env("PATH", original_path)
        File.rm_rf!(mock_dir)
      end)

      {:ok, mock_dir: mock_dir}
    end

    test "handles successful query response", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # This should use our mock CLI
      response = GenServer.call(session, {:query_sync, "test prompt", []}, 5000)

      assert response == {:ok, "Hello from mock CLI!"}

      GenServer.stop(session)
    end
  end

  describe "error handling" do
    test "handles CLI not found" do
      # Temporarily clear PATH to ensure CLI is not found
      original_path = System.get_env("PATH")
      System.put_env("PATH", "")

      {:ok, session} = Session.start_link(api_key: "test-key")

      response = GenServer.call(session, {:query_sync, "test", []})

      assert {:error, {:cli_not_found, _message}} = response

      System.put_env("PATH", original_path)
      GenServer.stop(session)
    end
  end

  describe "message processing" do
    test "processes assistant messages correctly" do
      {:ok, session} = Session.start_link(api_key: "test-key")

      # Simulate receiving data from the port
      state = :sys.get_state(session)

      # Add a pending request
      from = {self(), make_ref()}
      request_id = make_ref()

      _state = %{
        state
        | pending_requests: %{
            request_id => %{from: from, buffer: "", messages: []}
          }
      }

      # Send a mock message through the session
      json_line = ~s({"type": "assistant", "message": {"content": [{"text": "Test response", "type": "text"}]}}\n)

      # We need to simulate the port message
      send(session, {nil, {:data, json_line}})

      # Wait a bit for processing
      Process.sleep(100)

      GenServer.stop(session)
    end
  end
end
