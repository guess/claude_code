defmodule ClaudeCode.Session.ServerTest do
  use ExUnit.Case, async: true

  @adapter {ClaudeCode.Test, ClaudeCode}

  setup do
    ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
      [
        ClaudeCode.Test.text("ok"),
        ClaudeCode.Test.result("ok")
      ]
    end)

    {:ok, session} = ClaudeCode.Session.start_link(adapter: @adapter)
    on_exit(fn -> if Process.alive?(session), do: ClaudeCode.stop(session) end)
    {:ok, session: session}
  end

  describe "{:adapter_call, m, f, a}" do
    test "executes MFA via adapter and returns result", %{session: session} do
      result = GenServer.call(session, {:adapter_call, String, :upcase, ["hello"]})
      assert result == "HELLO"
    end

    test "returns error tuples unchanged", %{session: session} do
      result = GenServer.call(session, {:adapter_call, File, :read, ["/nonexistent/path"]})
      assert {:error, :enoent} = result
    end
  end

  describe "{:history_call, function, opts}" do
    test "returns {:ok, []} when no session_id", %{session: session} do
      result = GenServer.call(session, {:history_call, :get_messages, []})
      assert result == {:ok, []}
    end

    test "injects project_path from session cwd" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [
          ClaudeCode.Test.text("ok"),
          ClaudeCode.Test.result("ok")
        ]
      end)

      {:ok, session} =
        ClaudeCode.Session.start_link(
          adapter: {ClaudeCode.Test, ClaudeCode},
          cwd: "/tmp/test-project"
        )

      on_exit(fn -> if Process.alive?(session), do: ClaudeCode.stop(session) end)

      # Make a query so session_id gets captured
      session |> ClaudeCode.stream("hi") |> Stream.run()

      # Verify session_id was captured
      state = :sys.get_state(session)
      assert is_binary(state.session_id)

      # history_call calls History.get_messages(session_id, project_path: "/tmp/test-project")
      # Returns {:ok, []} since no actual JSONL file exists — exercises the plumbing
      result = GenServer.call(session, {:history_call, :get_messages, []})
      assert {:ok, []} = result
    end

    test "caller opts take precedence over injected defaults" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [
          ClaudeCode.Test.text("ok"),
          ClaudeCode.Test.result("ok")
        ]
      end)

      {:ok, session} =
        ClaudeCode.Session.start_link(
          adapter: {ClaudeCode.Test, ClaudeCode},
          cwd: "/tmp/default-project"
        )

      on_exit(fn -> if Process.alive?(session), do: ClaudeCode.stop(session) end)

      session |> ClaudeCode.stream("hi") |> Stream.run()

      # Caller provides explicit project_path — should not be overridden by cwd
      result =
        GenServer.call(
          session,
          {:history_call, :get_messages, [project_path: "/tmp/custom-project"]}
        )

      assert {:ok, []} = result
    end
  end
end
