defmodule ClaudeCode.Adapter.LocalTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Local

  # ============================================================================
  # shell_escape/1 Tests
  # ============================================================================

  describe "shell_escape/1" do
    test "returns simple strings unchanged" do
      assert Local.shell_escape("hello") == "hello"
      assert Local.shell_escape("foo123") == "foo123"
      assert Local.shell_escape("path/to/file") == "path/to/file"
    end

    test "escapes empty strings" do
      assert Local.shell_escape("") == "''"
    end

    test "escapes strings with spaces" do
      assert Local.shell_escape("hello world") == "'hello world'"
      assert Local.shell_escape("path with spaces") == "'path with spaces'"
    end

    test "escapes strings with single quotes" do
      assert Local.shell_escape("it's") == "'it'\\''s'"
      assert Local.shell_escape("don't") == "'don'\\''t'"
    end

    test "escapes strings with double quotes" do
      assert Local.shell_escape("say \"hello\"") == "'say \"hello\"'"
    end

    test "escapes strings with dollar signs" do
      assert Local.shell_escape("$HOME") == "'$HOME'"
      assert Local.shell_escape("cost: $100") == "'cost: $100'"
    end

    test "escapes strings with backticks" do
      assert Local.shell_escape("`command`") == "'`command`'"
    end

    test "escapes strings with backslashes" do
      assert Local.shell_escape("path\\to\\file") == "'path\\to\\file'"
    end

    test "escapes strings with newlines" do
      assert Local.shell_escape("line1\nline2") == "'line1\nline2'"
    end

    test "escapes strings with multiple special characters" do
      assert Local.shell_escape("it's $100") == "'it'\\''s $100'"
      assert Local.shell_escape("say \"hi\" to '$USER'") == "'say \"hi\" to '\\''$USER'\\'''"
    end

    test "escapes strings with semicolons (command separator)" do
      # Critical for env vars like LS_COLORS which contain semicolons
      assert Local.shell_escape("rs=0:di=01;34") == "'rs=0:di=01;34'"
      assert Local.shell_escape("cmd1;cmd2") == "'cmd1;cmd2'"
    end

    test "escapes strings with ampersands (background/and operator)" do
      assert Local.shell_escape("cmd1&cmd2") == "'cmd1&cmd2'"
      assert Local.shell_escape("cmd1 && cmd2") == "'cmd1 && cmd2'"
    end

    test "escapes strings with pipes (command chaining)" do
      assert Local.shell_escape("cmd1|cmd2") == "'cmd1|cmd2'"
      assert Local.shell_escape("cmd1 | cmd2") == "'cmd1 | cmd2'"
    end

    test "escapes strings with parentheses (subshell)" do
      assert Local.shell_escape("(cmd)") == "'(cmd)'"
      assert Local.shell_escape("$(cmd)") == "'$(cmd)'"
    end

    test "converts non-strings to strings" do
      assert Local.shell_escape(123) == "123"
      assert Local.shell_escape(:atom) == "atom"
    end
  end

  # ============================================================================
  # extract_lines/1 Tests
  # ============================================================================

  describe "extract_lines/1" do
    test "extracts complete lines from buffer" do
      {lines, remaining} = Local.extract_lines("line1\nline2\nline3\n")
      assert lines == ["line1", "line2", "line3"]
      assert remaining == ""
    end

    test "keeps incomplete line in remaining buffer" do
      {lines, remaining} = Local.extract_lines("line1\nline2\nincomplete")
      assert lines == ["line1", "line2"]
      assert remaining == "incomplete"
    end

    test "handles empty buffer" do
      {lines, remaining} = Local.extract_lines("")
      assert lines == []
      assert remaining == ""
    end

    test "handles buffer with no complete lines" do
      {lines, remaining} = Local.extract_lines("partial")
      assert lines == []
      assert remaining == "partial"
    end

    test "handles buffer with single complete line" do
      {lines, remaining} = Local.extract_lines("single\n")
      assert lines == ["single"]
      assert remaining == ""
    end

    test "handles buffer with only newline" do
      {lines, remaining} = Local.extract_lines("\n")
      assert lines == [""]
      assert remaining == ""
    end

    test "handles buffer with multiple consecutive newlines" do
      {lines, remaining} = Local.extract_lines("line1\n\nline3\n")
      assert lines == ["line1", "", "line3"]
      assert remaining == ""
    end

    test "handles JSON lines (typical CLI output)" do
      json1 = ~s({"type":"system","subtype":"init"})
      json2 = ~s({"type":"assistant","message":{}})
      buffer = "#{json1}\n#{json2}\n"

      {lines, remaining} = Local.extract_lines(buffer)
      assert lines == [json1, json2]
      assert remaining == ""
    end

    test "handles partial JSON accumulation" do
      # First chunk
      {lines1, remaining1} = Local.extract_lines(~s({"type":"sys))
      assert lines1 == []
      assert remaining1 == ~s({"type":"sys)

      # Second chunk arrives
      {lines2, remaining2} = Local.extract_lines(remaining1 <> ~s(tem"}\n{"type":))
      assert lines2 == [~s({"type":"system"})]
      assert remaining2 == ~s({"type":)

      # Final chunk
      {lines3, remaining3} = Local.extract_lines(remaining2 <> ~s("result"}\n))
      assert lines3 == [~s({"type":"result"})]
      assert remaining3 == ""
    end
  end

  # ============================================================================
  # Adapter Behaviour Tests
  # ============================================================================

  describe "adapter behaviour" do
    test "implements ClaudeCode.Adapter behaviour" do
      behaviours = Local.__info__(:attributes)[:behaviour] || []
      assert ClaudeCode.Adapter in behaviours
    end
  end

  describe "new behaviour callbacks" do
    test "implements all ClaudeCode.Adapter callbacks" do
      callbacks = ClaudeCode.Adapter.behaviour_info(:callbacks)

      Enum.each(callbacks, fn {fun, arity} ->
        assert function_exported?(ClaudeCode.Adapter.Local, fun, arity),
               "Missing callback: #{fun}/#{arity}"
      end)
    end
  end

  # ============================================================================
  # Adapter Status Lifecycle Tests
  # ============================================================================

  describe "adapter status lifecycle" do
    test "starts in provisioning status and transitions to ready" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      state = :sys.get_state(adapter)
      assert state.status == :ready
      assert state.port != nil

      GenServer.stop(adapter)
    end

    test "transitions to disconnected on provisioning failure" do
      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: "/nonexistent/path/to/claude"
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, {:error, _reason}}, 5000

      state = :sys.get_state(adapter)
      assert state.status == :disconnected
      assert state.port == nil

      GenServer.stop(adapter)
    end

    test "ensure_connected returns error during provisioning" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # Simulate provisioning state by replacing the adapter's state
      # This tests the ensure_connected guard clause directly
      :sys.replace_state(adapter, fn state ->
        %{state | status: :provisioning, port: nil}
      end)

      result = Local.send_query(adapter, make_ref(), "test", [])

      assert {:error, :provisioning} = result

      GenServer.stop(adapter)
    end
  end

  # ============================================================================
  # Environment Variable Tests
  # ============================================================================

  describe "sdk_env_vars/0" do
    test "returns SDK-required environment variables" do
      env = Local.sdk_env_vars()

      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
    end

    test "version matches application version" do
      env = Local.sdk_env_vars()
      expected_version = :claude_code |> Application.spec(:vsn) |> to_string()

      assert env["CLAUDE_AGENT_SDK_VERSION"] == expected_version
    end
  end

  describe "build_env/2" do
    test "includes system environment variables" do
      # Set a known system env var for the test
      System.put_env("CLAUDE_CODE_TEST_VAR", "test_value")

      try do
        env = Local.build_env([], nil)

        assert env["CLAUDE_CODE_TEST_VAR"] == "test_value"
      after
        System.delete_env("CLAUDE_CODE_TEST_VAR")
      end
    end

    test "user env overrides system env" do
      System.put_env("CLAUDE_CODE_TEST_VAR", "system_value")

      try do
        env = Local.build_env([env: %{"CLAUDE_CODE_TEST_VAR" => "user_value"}], nil)

        assert env["CLAUDE_CODE_TEST_VAR"] == "user_value"
      after
        System.delete_env("CLAUDE_CODE_TEST_VAR")
      end
    end

    test "SDK vars are always present" do
      env = Local.build_env([], nil)

      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
    end

    test "SDK vars override user env" do
      # User cannot override SDK-required vars
      env =
        Local.build_env(
          [
            env: %{
              "CLAUDE_CODE_ENTRYPOINT" => "malicious",
              "CLAUDE_AGENT_SDK_VERSION" => "0.0.0"
            }
          ],
          nil
        )

      # SDK vars win
      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
    end

    test "api_key overrides ANTHROPIC_API_KEY from system" do
      System.put_env("ANTHROPIC_API_KEY", "system_key")

      try do
        env = Local.build_env([], "option_api_key")

        assert env["ANTHROPIC_API_KEY"] == "option_api_key"
      after
        System.delete_env("ANTHROPIC_API_KEY")
      end
    end

    test "api_key overrides ANTHROPIC_API_KEY from user env" do
      env =
        Local.build_env(
          [env: %{"ANTHROPIC_API_KEY" => "user_env_key"}],
          "option_api_key"
        )

      assert env["ANTHROPIC_API_KEY"] == "option_api_key"
    end

    test "user env ANTHROPIC_API_KEY used when no api_key option" do
      env = Local.build_env([env: %{"ANTHROPIC_API_KEY" => "user_env_key"}], nil)

      assert env["ANTHROPIC_API_KEY"] == "user_env_key"
    end

    test "default empty env option" do
      # When :env not specified, defaults to empty map
      env = Local.build_env([], nil)

      # Should still have SDK vars
      assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
    end

    test "custom environment variables are passed through" do
      env =
        Local.build_env(
          [
            env: %{
              "MY_CUSTOM_VAR" => "custom_value",
              "ANOTHER_VAR" => "another_value"
            }
          ],
          nil
        )

      assert env["MY_CUSTOM_VAR"] == "custom_value"
      assert env["ANOTHER_VAR"] == "another_value"
    end

    test "preserves PATH from system" do
      path = System.get_env("PATH")

      env = Local.build_env([], nil)

      assert env["PATH"] == path
    end

    test "allows extending PATH" do
      original_path = System.get_env("PATH")
      extended_path = "/custom/bin:#{original_path}"

      env = Local.build_env([env: %{"PATH" => extended_path}], nil)

      assert env["PATH"] == extended_path
    end

    test "sets file checkpointing env var when enabled" do
      env = Local.build_env([enable_file_checkpointing: true], nil)

      assert env["CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"] == "true"
    end

    test "does not set file checkpointing env var when disabled" do
      env = Local.build_env([enable_file_checkpointing: false], nil)

      refute Map.has_key?(env, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")
    end

    test "does not set file checkpointing env var by default" do
      env = Local.build_env([], nil)

      refute Map.has_key?(env, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING")
    end
  end

  # ============================================================================
  # Control Message Routing Tests (Task 4)
  # ============================================================================

  describe "control message routing" do
    test "control_response messages do not reach session as adapter_message" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        INIT_DONE=false
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
            if [ "$INIT_DONE" = false ]; then
              INIT_DONE=true
              # Emit a stray control_response after init - should NOT reach session
              echo '{"type":"control_response","response":{"subtype":"success","request_id":"req_stray_test","response":{}}}'
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # We should NOT receive the control_response as an adapter_message
      refute_receive {:adapter_message, _, _}, 500

      GenServer.stop(adapter)
    end

    test "regular messages still reach session as adapter_message" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
          else
            echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Hello"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"test-123"}'
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test-123","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      req_ref = make_ref()
      :ok = Local.send_query(adapter, req_ref, "hello", [])

      assert_receive {:adapter_message, ^req_ref, _msg}, 5000
      assert_receive {:adapter_done, ^req_ref, :completed}, 5000

      GenServer.stop(adapter)
    end
  end

  # ============================================================================
  # Outbound Control Request Tests (Task 5)
  # ============================================================================

  describe "outbound control requests" do
    test "send_control_request sends control message and resolves on response" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{\\\"status\\\":\\\"ok\\\"}}}"
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      assert {:ok, %{"status" => "ok"}} =
               GenServer.call(adapter, {:control_request, :mcp_status, %{}})

      GenServer.stop(adapter)
    end

    test "send_control_request returns error on error response" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        INIT_DONE=false
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            if [ "$INIT_DONE" = false ]; then
              INIT_DONE=true
              echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
            else
              echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"error\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"error\\\":\\\"Something went wrong\\\"}}"
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      assert {:error, "Something went wrong"} =
               GenServer.call(adapter, {:control_request, :set_model, %{model: "opus"}})

      GenServer.stop(adapter)
    end

    test "control request times out when no response received" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        INIT_DONE=false
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            if [ "$INIT_DONE" = false ]; then
              INIT_DONE=true
              echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{}}}"
            else
              true
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      task =
        Task.async(fn ->
          GenServer.call(adapter, {:control_request, :mcp_status, %{}}, 5000)
        end)

      # Wait for the request to be sent
      Process.sleep(200)

      # Get the pending request ID and trigger timeout manually
      state = :sys.get_state(adapter)
      [req_id | _] = Map.keys(state.pending_control_requests)
      send(adapter, {:control_timeout, req_id})

      assert {:error, :control_timeout} = Task.await(task)

      GenServer.stop(adapter)
    end
  end

  # ============================================================================
  # Initialize Handshake Tests (Task 6)
  # ============================================================================

  describe "initialize handshake" do
    test "sends initialize request after port opens and caches server_info" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"subtype":"initialize"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{\\\"commands\\\":[\\\"query\\\"],\\\"capabilities\\\":{\\\"control\\\":true}}}}"
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 10_000

      state = :sys.get_state(adapter)
      assert state.server_info == %{"commands" => ["query"], "capabilities" => %{"control" => true}}

      GenServer.stop(adapter)
    end

    test "transitions to error on initialize timeout" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        # Never respond to initialize
        while IFS= read -r line; do
          true
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000

      # Wait for port to open and initialize to be sent
      Process.sleep(500)

      # Manually trigger timeout
      state = :sys.get_state(adapter)

      case Map.keys(state.pending_control_requests) do
        [req_id | _] -> send(adapter, {:control_timeout, req_id})
        _ -> :ok
      end

      assert_receive {:adapter_status, {:error, :initialize_timeout}}, 5000

      GenServer.stop(adapter)
    end

    test "passes agents option through initialize handshake" do
      agents = %{"reviewer" => %{"prompt" => "Review code"}}

      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"subtype":"initialize"'; then
            if echo "$line" | grep -q '"agents"'; then
              REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
              echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"subtype\\\":\\\"success\\\",\\\"request_id\\\":\\\"$REQ_ID\\\",\\\"response\\\":{\\\"agents_received\\\":true}}}"
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script],
          agents: agents
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 10_000

      state = :sys.get_state(adapter)
      assert state.server_info["agents_received"] == true

      GenServer.stop(adapter)
    end
  end
end
