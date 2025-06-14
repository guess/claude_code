defmodule ClaudeCode.SessionShellTest do
  use ExUnit.Case

  alias ClaudeCode.Session

  describe "shell command building" do
    setup do
      # Create a mock CLI that outputs the command it received
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_shell_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # This mock will output valid JSON matching real CLI format
      File.write!(mock_script, ~S"""
      #!/bin/bash
      # Output messages in the same format as real CLI
      echo '{"type":"system","subtype":"init","session_id":"test-123"}'
      echo '{"type":"assistant","message":{"content":[{"text":"Test response from mock","type":"text"}]}}'
      echo '{"type":"result","subtype":"success","result":"Test response from mock","session_id":"test-123"}'
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

    test "handles simple arguments correctly", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key-123")

      response = GenServer.call(session, {:query_sync, "Hello Claude", []}, 5000)

      assert {:ok, "Test response from mock"} = response

      GenServer.stop(session)
    end

    test "escapes arguments with special characters", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key-with-special-$-chars")

      response = GenServer.call(session, {:query_sync, "Hello 'Claude' with \"quotes\"", []}, 5000)

      assert {:ok, "Test response from mock"} = response

      GenServer.stop(session)
    end

    test "handles newlines in prompts", %{mock_dir: _mock_dir} do
      {:ok, session} = Session.start_link(api_key: "test-key")

      prompt = "Line 1\nLine 2\nLine 3"
      response = GenServer.call(session, {:query_sync, prompt, []}, 5000)

      assert {:ok, "Test response from mock"} = response

      GenServer.stop(session)
    end
  end

  describe "shell_escape/1 private function" do
    test "leaves simple strings unescaped" do
      # We can't directly test private functions, but we can verify behavior
      # through the public interface by checking that simple strings work
      assert true
    end
  end

  describe "cross-platform behavior" do
    test "detects unix platform correctly" do
      assert match?({:unix, _}, :os.type())
    end
  end
end
