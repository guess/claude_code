defmodule ClaudeCode.SupervisorTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Session.Server
  alias ClaudeCode.Supervisor, as: ClaudeSupervisor

  @api_key "test-api-key"

  describe "start_link/2" do
    test "starts supervisor with empty session list" do
      assert {:ok, supervisor} = ClaudeSupervisor.start_link([])
      assert Process.alive?(supervisor)

      # Should have no children initially
      assert ClaudeSupervisor.count_sessions(supervisor) == 0
    end

    test "starts supervisor with predefined sessions" do
      sessions = [
        [api_key: @api_key],
        [api_key: @api_key, model: "opus"]
      ]

      assert {:ok, supervisor} = ClaudeSupervisor.start_link(sessions)
      assert Process.alive?(supervisor)
      assert ClaudeSupervisor.count_sessions(supervisor) == 2

      Enum.each(ClaudeSupervisor.list_sessions(supervisor), fn {_id, pid, type, modules} ->
        assert is_pid(pid)
        assert type == :worker
        assert modules == [Server]
      end)
    end

    test "starts supervisor with custom name" do
      assert {:ok, supervisor} =
               ClaudeSupervisor.start_link([], name: :sup_custom_supervisor)

      assert Process.whereis(:sup_custom_supervisor) == supervisor
    end

    test "starts supervisor with custom supervision options" do
      sessions = [[api_key: @api_key]]

      assert {:ok, supervisor} =
               ClaudeSupervisor.start_link(sessions,
                 strategy: :one_for_one,
                 max_restarts: 5,
                 max_seconds: 10
               )

      assert Process.alive?(supervisor)
      assert ClaudeSupervisor.count_sessions(supervisor) == 1
    end

    test "handles session startup with empty config" do
      # Empty config is valid — api_key defaults to ANTHROPIC_API_KEY env var.
      # The child starts successfully and stays alive.
      sessions = [[]]

      assert {:ok, supervisor} = ClaudeSupervisor.start_link(sessions)
      assert Process.alive?(supervisor)
      assert ClaudeSupervisor.count_sessions(supervisor) == 1
    end
  end

  describe "start_session/3" do
    setup do
      {:ok, supervisor} = ClaudeSupervisor.start_link([])
      %{supervisor: supervisor}
    end

    test "starts a new session dynamically", %{supervisor: supervisor} do
      assert {:ok, _pid} =
               ClaudeSupervisor.start_session(supervisor, api_key: @api_key)

      assert ClaudeSupervisor.count_sessions(supervisor) == 1

      assert [{_id, pid, :worker, [Server]}] =
               ClaudeSupervisor.list_sessions(supervisor)

      assert is_pid(pid)
    end

    test "starts session with custom child ID", %{supervisor: supervisor} do
      assert {:ok, _pid} =
               ClaudeSupervisor.start_session(supervisor, [api_key: @api_key], id: :custom_id)

      assert [{:custom_id, _pid, :worker, [Server]}] =
               ClaudeSupervisor.list_sessions(supervisor)
    end

    test "prevents duplicate session names", %{supervisor: supervisor} do
      session_config = [name: :sup_duplicate_session, api_key: @api_key]

      assert {:ok, _pid} = ClaudeSupervisor.start_session(supervisor, session_config)

      assert {:error, {:already_started, _pid}} =
               ClaudeSupervisor.start_session(supervisor, session_config)

      assert ClaudeSupervisor.count_sessions(supervisor) == 1
    end

    test "starts session with empty config", %{supervisor: supervisor} do
      # Empty config is valid — api_key defaults to ANTHROPIC_API_KEY env var.
      # The child starts successfully.
      assert {:ok, pid} = ClaudeSupervisor.start_session(supervisor, [])
      assert Process.alive?(pid)
      assert ClaudeSupervisor.count_sessions(supervisor) == 1
    end
  end

  describe "terminate_session/2" do
    setup do
      {:ok, supervisor} = ClaudeSupervisor.start_link([])
      {:ok, _pid} = ClaudeSupervisor.start_session(supervisor, api_key: @api_key)
      [{child_id, _pid, _, _}] = ClaudeSupervisor.list_sessions(supervisor)

      %{supervisor: supervisor, child_id: child_id}
    end

    test "terminates an existing session", %{supervisor: supervisor, child_id: child_id} do
      assert ClaudeSupervisor.count_sessions(supervisor) == 1

      assert :ok = ClaudeSupervisor.terminate_session(supervisor, child_id)
      assert ClaudeSupervisor.count_sessions(supervisor) == 0
    end

    test "returns error for non-existent session", %{supervisor: supervisor} do
      assert {:error, :not_found} =
               ClaudeSupervisor.terminate_session(supervisor, :non_existent)

      assert ClaudeSupervisor.count_sessions(supervisor) == 1
    end
  end

  describe "list_sessions/1" do
    test "returns empty list for supervisor with no sessions" do
      {:ok, supervisor} = ClaudeSupervisor.start_link([])
      assert ClaudeSupervisor.list_sessions(supervisor) == []
    end

    test "returns list of active sessions" do
      sessions = [
        [api_key: @api_key],
        [api_key: @api_key]
      ]

      {:ok, supervisor} = ClaudeSupervisor.start_link(sessions)
      children = ClaudeSupervisor.list_sessions(supervisor)

      assert length(children) == 2

      Enum.each(children, fn {_id, pid, type, modules} ->
        assert is_pid(pid)
        assert type == :worker
        assert modules == [Server]
      end)
    end
  end

  describe "count_sessions/1" do
    test "returns 0 for empty supervisor" do
      {:ok, supervisor} = ClaudeSupervisor.start_link([])
      assert ClaudeSupervisor.count_sessions(supervisor) == 0
    end

    test "returns correct count for supervisor with sessions" do
      sessions = [
        [api_key: @api_key],
        [api_key: @api_key],
        [api_key: @api_key]
      ]

      {:ok, supervisor} = ClaudeSupervisor.start_link(sessions)
      assert ClaudeSupervisor.count_sessions(supervisor) == 3
    end
  end

  describe "restart_session/2" do
    setup do
      {:ok, supervisor} = ClaudeSupervisor.start_link([])
      {:ok, original_pid} = ClaudeSupervisor.start_session(supervisor, api_key: @api_key)
      [{child_id, _, _, _}] = ClaudeSupervisor.list_sessions(supervisor)

      %{supervisor: supervisor, child_id: child_id, original_pid: original_pid}
    end

    test "restarts an existing session",
         %{supervisor: supervisor, child_id: child_id, original_pid: original_pid} do
      case ClaudeSupervisor.restart_session(supervisor, child_id) do
        :ok ->
          :ok

        {:error, :running} ->
          ClaudeSupervisor.terminate_session(supervisor, child_id)
          ClaudeSupervisor.start_session(supervisor, [api_key: @api_key], id: child_id)
      end

      assert ClaudeSupervisor.count_sessions(supervisor) == 1

      MockCLI.poll_until(
        fn ->
          case ClaudeSupervisor.list_sessions(supervisor) do
            [{^child_id, new_pid, :worker, [Server]}] when new_pid != original_pid -> {:ok, new_pid}
            _ -> :retry
          end
        end,
        timeout: 2000
      )

      [{^child_id, new_pid, :worker, [Server]}] =
        ClaudeSupervisor.list_sessions(supervisor)

      assert Process.alive?(new_pid)
      refute Process.alive?(original_pid)
    end

    test "returns error for non-existent session", %{supervisor: supervisor} do
      assert {:error, :not_found} =
               ClaudeSupervisor.restart_session(supervisor, :non_existent)
    end
  end

  describe "fault tolerance" do
    test "restarts crashed sessions automatically" do
      sessions = [[api_key: @api_key]]

      {:ok, supervisor} = ClaudeSupervisor.start_link(sessions)
      assert ClaudeSupervisor.count_sessions(supervisor) == 1

      [{child_id, original_pid, :worker, [Server]}] =
        ClaudeSupervisor.list_sessions(supervisor)

      Process.exit(original_pid, :kill)

      MockCLI.poll_until(
        fn ->
          case ClaudeSupervisor.list_sessions(supervisor) do
            [{^child_id, new_pid, :worker, [Server]}] when new_pid != original_pid -> {:ok, new_pid}
            _ -> :retry
          end
        end,
        timeout: 2000
      )

      assert ClaudeSupervisor.count_sessions(supervisor) == 1

      [{^child_id, new_pid, :worker, [Server]}] =
        ClaudeSupervisor.list_sessions(supervisor)

      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end

    test "handles multiple session crashes independently" do
      sessions = [
        [api_key: @api_key],
        [api_key: @api_key],
        [api_key: @api_key]
      ]

      {:ok, supervisor} = ClaudeSupervisor.start_link(sessions)
      assert ClaudeSupervisor.count_sessions(supervisor) == 3

      children = ClaudeSupervisor.list_sessions(supervisor)
      pids = Enum.map(children, fn {_id, pid, _type, _modules} -> pid end)

      [first_pid | other_pids] = pids
      Process.exit(first_pid, :kill)

      MockCLI.poll_until(
        fn ->
          if ClaudeSupervisor.count_sessions(supervisor) == 3 do
            children = ClaudeSupervisor.list_sessions(supervisor)
            child_pids = Enum.map(children, fn {_id, pid, _type, _modules} -> pid end)
            if first_pid in child_pids, do: :retry, else: {:ok, child_pids}
          else
            :retry
          end
        end,
        timeout: 2000
      )

      assert ClaudeSupervisor.count_sessions(supervisor) == 3

      Enum.each(other_pids, fn pid ->
        assert Process.alive?(pid)
      end)
    end
  end

  describe "integration with ClaudeCode.Session" do
    @tag :integration
    test "supervised sessions can be queried by name" do
      sessions = [
        [name: :sup_query_session, api_key: @api_key]
      ]

      {:ok, supervisor} = ClaudeSupervisor.start_link(sessions)

      [{:sup_query_session, session_pid, :worker, [Server]}] =
        ClaudeSupervisor.list_sessions(supervisor)

      assert Process.whereis(:sup_query_session) == session_pid
      assert Process.alive?(session_pid)
    end
  end
end
