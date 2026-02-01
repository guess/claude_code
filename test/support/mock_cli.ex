defmodule MockCLI do
  @moduledoc """
  Test helper for creating mock Claude CLI scripts.

  Provides a clean API for setting up mock CLI scripts that output
  predefined JSON messages, eliminating duplication in tests.

  ## Usage

      setup do
        MockCLI.setup([
          MockCLI.system_message(),
          MockCLI.assistant_message(text: "Hello"),
          MockCLI.result_message(result: "Done")
        ])
      end

  ## Advanced Usage

  For custom scripts with logic, use `setup_with_script/2` with custom bash code.
  """

  @doc """
  Sets up a mock CLI with the given messages.

  Creates a temporary directory with a mock `claude` script, modifies PATH,
  and registers cleanup callbacks. Returns `{:ok, mock_dir: path}` for use
  in test context.

  ## Options

    * `:messages` - List of message maps to output (required)
    * `:script_name` - Name of the mock script (default: "claude")
    * `:sleep` - Sleep duration in seconds between messages (default: 0)

  ## Examples

      setup do
        MockCLI.setup([
          MockCLI.system_message(),
          MockCLI.result_message()
        ])
      end

      setup do
        MockCLI.setup(
          [MockCLI.system_message(), MockCLI.result_message()],
          sleep: 0.1
        )
      end
  """
  def setup(messages, opts \\ []) do
    sleep = Keyword.get(opts, :sleep, 0)
    script_name = Keyword.get(opts, :script_name, "claude")

    script_body = build_script(messages, sleep)
    setup_with_script(script_body, script_name: script_name)
  end

  @doc """
  Sets up a mock CLI with a custom bash script.

  Useful for advanced scenarios requiring custom logic or argument parsing.

  The script should output newline-delimited JSON messages matching the
  Claude CLI format (system, assistant, result messages).
  """
  def setup_with_script(script_content, opts \\ []) do
    script_name = Keyword.get(opts, :script_name, "claude")

    # Create unique temporary directory
    mock_dir = Path.join(System.tmp_dir!(), "claude_code_mock_#{:rand.uniform(100_000)}")
    File.mkdir_p!(mock_dir)

    # Write and make executable
    mock_script = Path.join(mock_dir, script_name)
    File.write!(mock_script, script_content)
    File.chmod!(mock_script, 0o755)

    # Register cleanup
    ExUnit.Callbacks.on_exit(fn ->
      File.rm_rf!(mock_dir)
    end)

    # Return both mock_dir and mock_script for tests to use with cli_path option
    {:ok, mock_dir: mock_dir, mock_script: mock_script}
  end

  @doc """
  Creates a system initialization message.

  ## Options

    * `:session_id` - Session ID (default: random UUID)
    * `:model` - Model name (default: "claude-3")
    * `:cwd` - Current working directory (default: "/test")
    * `:tools` - List of tool names (default: [])
    * `:mcp_servers` - List of MCP servers (default: [])
  """
  def system_message(opts \\ []) do
    %{
      type: "system",
      subtype: "init",
      cwd: Keyword.get(opts, :cwd, "/test"),
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      tools: Keyword.get(opts, :tools, []),
      mcp_servers: Keyword.get(opts, :mcp_servers, []),
      model: Keyword.get(opts, :model, "claude-3"),
      permissionMode: Keyword.get(opts, :permission_mode, "auto"),
      apiKeySource: Keyword.get(opts, :api_key_source, "ANTHROPIC_API_KEY")
    }
  end

  @doc """
  Creates an assistant message with text content.

  ## Options

    * `:text` - Text content (default: "Hello")
    * `:session_id` - Session ID (default: "test-123")
    * `:message_id` - Message ID (default: "msg_1")
    * `:model` - Model name (default: "claude-3")
    * `:stop_reason` - Stop reason (default: nil)
    * `:usage` - Usage map (default: %{})
  """
  def assistant_message(opts \\ []) do
    %{
      type: "assistant",
      message: %{
        id: Keyword.get(opts, :message_id, "msg_1"),
        type: "message",
        role: "assistant",
        model: Keyword.get(opts, :model, "claude-3"),
        content: [
          %{
            type: "text",
            text: Keyword.get(opts, :text, "Hello")
          }
        ],
        stop_reason: Keyword.get(opts, :stop_reason),
        stop_sequence: nil,
        usage: Keyword.get(opts, :usage, %{})
      },
      parent_tool_use_id: Keyword.get(opts, :parent_tool_use_id),
      session_id: Keyword.get(opts, :session_id, "test-123")
    }
  end

  @doc """
  Creates a result message.

  ## Options

    * `:result` - Result text (default: "Success")
    * `:session_id` - Session ID (default: "test-123")
    * `:is_error` - Whether this is an error (default: false)
    * `:subtype` - Result subtype (default: "success")
    * `:duration_ms` - Duration in milliseconds (default: 100)
    * `:duration_api_ms` - API duration in milliseconds (default: 80)
    * `:num_turns` - Number of turns (default: 1)
    * `:total_cost_usd` - Total cost in USD (default: 0.001)
    * `:usage` - Usage map (default: %{})
  """
  def result_message(opts \\ []) do
    %{
      type: "result",
      subtype: Keyword.get(opts, :subtype, "success"),
      is_error: Keyword.get(opts, :is_error, false),
      duration_ms: Keyword.get(opts, :duration_ms, 100),
      duration_api_ms: Keyword.get(opts, :duration_api_ms, 80),
      num_turns: Keyword.get(opts, :num_turns, 1),
      result: Keyword.get(opts, :result, "Success"),
      session_id: Keyword.get(opts, :session_id, "test-123"),
      total_cost_usd: Keyword.get(opts, :total_cost_usd, 0.001),
      usage: Keyword.get(opts, :usage, %{})
    }
  end

  @doc """
  Encodes a message map to JSON string.

  Useful when building custom scripts.
  """
  def encode_json(message) do
    Jason.encode!(message)
  end

  @doc """
  Helper to perform a sync-like query on a session using streaming.

  This is useful for tests that need to verify query results without
  dealing with stream iteration. Returns `{:ok, result}` or `{:error, reason}`.
  """
  def sync_query(session, prompt, opts \\ []) do
    alias ClaudeCode.Message.ResultMessage

    session
    |> ClaudeCode.stream(prompt, opts)
    |> Enum.reduce(nil, fn
      %ResultMessage{} = result, _acc -> result
      _msg, acc -> acc
    end)
    |> case do
      %ResultMessage{is_error: true} = result -> {:error, result}
      %ResultMessage{} = result -> {:ok, result}
      nil -> {:error, :no_result}
    end
  end

  # Private helpers

  defp build_script(messages, sleep) do
    # Build a streaming-aware script that:
    # 1. Reads input from stdin (newline-delimited JSON)
    # 2. For each input, outputs the configured messages
    # 3. Keeps running until stdin is closed
    message_lines =
      Enum.map_join(messages, "\n", fn msg ->
        json = encode_json(msg)
        # Escape single quotes for shell
        escaped_json = String.replace(json, "'", "'\\''")

        if sleep > 0 do
          "echo '#{escaped_json}'\nsleep #{sleep}"
        else
          "echo '#{escaped_json}'"
        end
      end)

    """
    #!/bin/bash
    # Streaming mode: read from stdin and output messages for each input
    while IFS= read -r line; do
      #{message_lines}
    done
    exit 0
    """
  end

  defp generate_session_id do
    "test-#{:rand.uniform(999_999)}"
  end
end
