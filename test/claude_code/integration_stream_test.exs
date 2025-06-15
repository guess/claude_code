defmodule ClaudeCode.IntegrationStreamTest do
  use ExUnit.Case

  alias ClaudeCode.Message.Assistant
  alias ClaudeCode.Message.Result

  describe "streaming integration with mock CLI" do
    setup do
      # Create a mock CLI that outputs messages gradually
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_integration_stream_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Write a more sophisticated mock that simulates streaming
      File.write!(mock_script, """
      #!/bin/bash
      # Simulate streaming response
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"stream-test","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
      sleep 0.05
      echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Once upon a time"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"stream-test"}'
      sleep 0.05
      echo '{"type":"assistant","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":", there was a developer"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"stream-test"}'
      sleep 0.05
      echo '{"type":"assistant","message":{"id":"msg_3","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":" who loved Elixir. "}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"stream-test"}'
      sleep 0.05
      echo '{"type":"assistant","message":{"id":"msg_4","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"The end."}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"stream-test"}'
      sleep 0.05
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":250,"duration_api_ms":200,"num_turns":1,"result":"Once upon a time, there was a developer who loved Elixir. The end.","session_id":"stream-test","total_cost_usd":0.001,"usage":{}}'
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

    test "query/3 returns a working stream", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      messages =
        session
        |> ClaudeCode.query("Tell me a story", timeout: 5000)
        |> Enum.to_list()

      # Should have multiple assistant messages and result
      # Note: System message is not included in stream as it's sent before the query
      assert length(messages) >= 4

      # Verify message types
      assistant_messages = Enum.filter(messages, &match?(%Assistant{}, &1))
      assert length(assistant_messages) >= 3

      result_messages = Enum.filter(messages, &match?(%Result{}, &1))
      assert length(result_messages) == 1

      ClaudeCode.stop(session)
    end

    test "text_content/1 extracts text properly", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      text_parts =
        session
        |> ClaudeCode.query("Tell me a story")
        |> ClaudeCode.Stream.text_content()
        |> Enum.to_list()

      assert text_parts == [
               "Once upon a time",
               ", there was a developer",
               " who loved Elixir. ",
               "The end."
             ]

      ClaudeCode.stop(session)
    end

    test "filter_type/2 filters correctly", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      # Get only assistant messages
      assistant_messages =
        session
        |> ClaudeCode.query("Tell me a story")
        |> ClaudeCode.Stream.filter_type(:assistant)
        |> Enum.to_list()

      assert Enum.all?(assistant_messages, &match?(%Assistant{}, &1))
      assert length(assistant_messages) >= 3

      ClaudeCode.stop(session)
    end

    test "buffered_text/1 buffers until sentence boundaries", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      buffered =
        session
        |> ClaudeCode.query("Tell me a story")
        |> ClaudeCode.Stream.buffered_text()
        |> Enum.to_list()

      # Should buffer text until sentence boundaries
      assert buffered == [
               "Once upon a time, there was a developer who loved Elixir. ",
               "The end."
             ]

      ClaudeCode.stop(session)
    end

    test "until_result/1 stops at result message", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      messages =
        session
        |> ClaudeCode.query("Tell me a story")
        |> ClaudeCode.Stream.until_result()
        |> Enum.to_list()

      # Should include all messages including result
      assert length(messages) >= 5

      # Last message should be result
      assert match?(%Result{}, List.last(messages))

      ClaudeCode.stop(session)
    end

    test "multiple queries work correctly", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      # First query
      text1 =
        session
        |> ClaudeCode.query("Tell me a story")
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      assert text1 == "Once upon a time, there was a developer who loved Elixir. The end."

      # Second query (new stream)
      text2 =
        session
        |> ClaudeCode.query("Tell me another story")
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      # Mock returns same response
      assert text2 == text1

      ClaudeCode.stop(session)
    end

    test "query_async/3 works correctly", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      {:ok, request_id} = ClaudeCode.query_async(session, "Tell me a story")

      # Collect messages manually
      messages = collect_messages(request_id, 1000)

      assert length(messages) >= 5
      assert Enum.any?(messages, &match?(%Result{}, &1))

      ClaudeCode.stop(session)
    end

    defp collect_messages(request_id, timeout) do
      collect_messages(request_id, timeout, [])
    end

    defp collect_messages(request_id, timeout, acc) do
      receive do
        {:claude_message, ^request_id, message} ->
          collect_messages(request_id, timeout, [message | acc])

        {:claude_stream_end, ^request_id} ->
          Enum.reverse(acc)
      after
        timeout ->
          Enum.reverse(acc)
      end
    end
  end

  describe "streaming with tool use mock" do
    setup do
      # Create a mock CLI that outputs tool use messages
      mock_dir = Path.join(System.tmp_dir!(), "claude_code_tool_stream_#{:rand.uniform(100_000)}")
      File.mkdir_p!(mock_dir)

      mock_script = Path.join(mock_dir, "claude")

      # Write a mock that includes tool use
      File.write!(mock_script, """
      #!/bin/bash
      echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"tool-test","tools":["write_file","read_file"],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
      sleep 0.05
      echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"I'"'"'ll create a file for you."}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"tool-test"}'
      sleep 0.05
      echo '{"type":"assistant","message":{"id":"msg_2","type":"message","role":"assistant","model":"claude-3","content":[{"type":"tool_use","id":"tool_1","name":"write_file","input":{"path":"test.txt","content":"Hello from Claude!"}}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"tool-test"}'
      sleep 0.05
      echo '{"type":"assistant","message":{"id":"msg_3","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"File created successfully!"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"tool-test"}'
      sleep 0.05
      echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":150,"duration_api_ms":100,"num_turns":1,"result":"Created test.txt","session_id":"tool-test","total_cost_usd":0.001,"usage":{}}'
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

    test "tool_uses/1 extracts tool use blocks", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      tool_uses =
        session
        |> ClaudeCode.query("Create a file")
        |> ClaudeCode.Stream.tool_uses()
        |> Enum.to_list()

      assert length(tool_uses) == 1

      tool_use = hd(tool_uses)
      assert tool_use.name == "write_file"
      assert tool_use.input == %{"path" => "test.txt", "content" => "Hello from Claude!"}

      ClaudeCode.stop(session)
    end

    test "filter by tool_use pseudo-type", %{mock_dir: _mock_dir} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key")

      tool_messages =
        session
        |> ClaudeCode.query("Create a file")
        |> ClaudeCode.Stream.filter_type(:tool_use)
        |> Enum.to_list()

      # Should only include assistant messages that contain tool uses
      assert length(tool_messages) == 1
      assert match?(%Assistant{}, hd(tool_messages))

      ClaudeCode.stop(session)
    end
  end
end
