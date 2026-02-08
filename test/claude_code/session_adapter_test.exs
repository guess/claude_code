defmodule ClaudeCode.SessionAdapterTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Session

  # ============================================================================
  # Session eager init failure (adapter start_link returns {:error, reason})
  # ============================================================================

  describe "eager init failure" do
    test "session fails to start when adapter start_link returns {:error, reason}" do
      Process.flag(:trap_exit, true)

      # Define a minimal failing adapter that always returns {:error, reason} from start_link
      defmodule FailingAdapter do
        @moduledoc false
        @behaviour ClaudeCode.Adapter

        @impl true
        def start_link(_session, _opts), do: {:error, :adapter_init_failed}

        @impl true
        def send_query(_adapter, _req_id, _prompt, _opts), do: :ok

        @impl true
        def interrupt(_adapter), do: :ok

        @impl true
        def health(_adapter), do: :healthy

        @impl true
        def stop(_adapter), do: :ok
      end

      # Starting a session with the failing adapter should fail
      result = Session.start_link(adapter: {FailingAdapter, []})

      assert {:error, :adapter_init_failed} = result
    end

    test "session fails to start with different error reasons" do
      Process.flag(:trap_exit, true)

      defmodule FailingAdapterTimeout do
        @moduledoc false
        @behaviour ClaudeCode.Adapter

        @impl true
        def start_link(_session, _opts), do: {:error, :connection_timeout}

        @impl true
        def send_query(_adapter, _req_id, _prompt, _opts), do: :ok

        @impl true
        def interrupt(_adapter), do: :ok

        @impl true
        def health(_adapter), do: :healthy

        @impl true
        def stop(_adapter), do: :ok
      end

      result = Session.start_link(adapter: {FailingAdapterTimeout, []})
      assert {:error, :connection_timeout} = result
    end
  end

  # ============================================================================
  # Session resolve_adapter/2 with {Module, config} tuple pattern
  # ============================================================================

  describe "resolve_adapter with {Module, config} tuple" do
    test "passes config keyword list to adapter start_link" do
      # Create an adapter that records what config it received
      defmodule ConfigCapturingAdapter do
        @moduledoc false
        @behaviour ClaudeCode.Adapter

        use GenServer

        @impl ClaudeCode.Adapter
        def start_link(session, opts) do
          GenServer.start_link(__MODULE__, {session, opts})
        end

        @impl ClaudeCode.Adapter
        def send_query(adapter, request_id, _prompt, _opts) do
          GenServer.cast(adapter, {:query, request_id})
          :ok
        end

        @impl ClaudeCode.Adapter
        def interrupt(_adapter), do: :ok

        @impl ClaudeCode.Adapter
        def health(_adapter), do: :healthy

        @impl ClaudeCode.Adapter
        def stop(adapter), do: GenServer.stop(adapter, :normal)

        @impl GenServer
        def init({session, opts}) do
          Process.link(session)
          {:ok, %{session: session, opts: opts}}
        end

        @impl GenServer
        def handle_cast({:query, request_id}, state) do
          send(state.session, {:adapter_done, request_id, :completed})
          {:noreply, state}
        end

        @impl GenServer
        def handle_call(:get_opts, _from, state) do
          {:reply, state.opts, state}
        end
      end

      custom_config = [my_key: "my_value", another_key: 42]

      {:ok, session} = Session.start_link(adapter: {ConfigCapturingAdapter, custom_config})

      # Verify the adapter was started and get its state
      state = :sys.get_state(session)
      adapter_pid = state.adapter_pid
      assert is_pid(adapter_pid)

      # The adapter should have received the config with :callers added
      adapter_opts = GenServer.call(adapter_pid, :get_opts)
      assert Keyword.get(adapter_opts, :my_key) == "my_value"
      assert Keyword.get(adapter_opts, :another_key) == 42
      # :callers is automatically injected by resolve_adapter
      assert is_list(Keyword.get(adapter_opts, :callers))

      GenServer.stop(session)
    end

    test "callers list contains the calling process" do
      defmodule CallerCheckAdapter do
        @moduledoc false
        @behaviour ClaudeCode.Adapter

        use GenServer

        @impl ClaudeCode.Adapter
        def start_link(session, opts) do
          GenServer.start_link(__MODULE__, {session, opts})
        end

        @impl ClaudeCode.Adapter
        def send_query(_adapter, _req_id, _prompt, _opts), do: :ok

        @impl ClaudeCode.Adapter
        def interrupt(_adapter), do: :ok

        @impl ClaudeCode.Adapter
        def health(_adapter), do: :healthy

        @impl ClaudeCode.Adapter
        def stop(adapter), do: GenServer.stop(adapter, :normal)

        @impl GenServer
        def init({session, opts}) do
          Process.link(session)
          {:ok, %{session: session, opts: opts}}
        end

        @impl GenServer
        def handle_call(:get_opts, _from, state) do
          {:reply, state.opts, state}
        end
      end

      test_pid = self()

      {:ok, session} = Session.start_link(adapter: {CallerCheckAdapter, [custom: true]})

      state = :sys.get_state(session)
      adapter_opts = GenServer.call(state.adapter_pid, :get_opts)

      callers = Keyword.get(adapter_opts, :callers)
      assert is_list(callers)
      assert test_pid in callers

      GenServer.stop(session)
    end
  end

  # ============================================================================
  # End-to-end interrupt: stream terminates cleanly on interrupt
  # ============================================================================

  describe "interrupt end-to-end with MockCLI" do
    setup do
      # Create a mock CLI that has a very slow response, allowing interrupt
      MockCLI.setup_with_script("""
      #!/bin/bash
      while IFS= read -r line; do
        # Output system message immediately
        echo '{"type":"system","subtype":"init","cwd":"/test","session_id":"e2e-int","tools":[],"mcp_servers":[],"model":"claude-3","permissionMode":"auto","apiKeySource":"ANTHROPIC_API_KEY"}'
        echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Starting..."}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"e2e-int"}'
        # Sleep long enough to allow interrupt
        sleep 30
        echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"Should not reach here","session_id":"e2e-int","total_cost_usd":0.001,"usage":{}}'
      done
      exit 0
      """)
    end

    test "stream terminates without hanging after interrupt", %{mock_script: mock_script} do
      {:ok, session} = ClaudeCode.start_link(api_key: "test-key", cli_path: mock_script)

      # Start streaming in a task
      stream_task =
        Task.async(fn ->
          session
          |> ClaudeCode.stream("long running query")
          |> Enum.to_list()
        end)

      # Wait for the stream to start and the adapter to send the first message
      Process.sleep(500)

      # Interrupt
      result = ClaudeCode.interrupt(session)
      assert result == :ok

      # The stream should terminate (not hang)
      messages = Task.await(stream_task, 5_000)
      assert is_list(messages)

      GenServer.stop(session)
    end
  end

  # ============================================================================
  # Session health delegation to adapter
  # ============================================================================

  describe "health delegation" do
    defmodule HealthyAdapter do
      @moduledoc false
      @behaviour ClaudeCode.Adapter

      use GenServer

      @impl ClaudeCode.Adapter
      def start_link(session, opts), do: GenServer.start_link(__MODULE__, {session, opts})

      @impl ClaudeCode.Adapter
      def send_query(_adapter, _req_id, _prompt, _opts), do: :ok

      @impl ClaudeCode.Adapter
      def interrupt(_adapter), do: :ok

      @impl ClaudeCode.Adapter
      def health(adapter), do: GenServer.call(adapter, :health)

      @impl ClaudeCode.Adapter
      def stop(adapter), do: GenServer.stop(adapter, :normal)

      @impl GenServer
      def init({session, opts}) do
        Process.link(session)
        {:ok, %{session: session, health: Keyword.get(opts, :health_status, :healthy)}}
      end

      @impl GenServer
      def handle_call(:health, _from, state) do
        {:reply, state.health, state}
      end
    end

    test "session passes through :healthy from adapter" do
      {:ok, session} = Session.start_link(adapter: {HealthyAdapter, [health_status: :healthy]})

      assert :healthy = ClaudeCode.health(session)

      GenServer.stop(session)
    end

    test "session passes through {:unhealthy, reason} from adapter" do
      {:ok, session} =
        Session.start_link(adapter: {HealthyAdapter, [health_status: {:unhealthy, :some_reason}]})

      assert {:unhealthy, :some_reason} = ClaudeCode.health(session)

      GenServer.stop(session)
    end

    test "session passes through :degraded from adapter" do
      {:ok, session} = Session.start_link(adapter: {HealthyAdapter, [health_status: :degraded]})

      assert :degraded = ClaudeCode.health(session)

      GenServer.stop(session)
    end
  end
end
