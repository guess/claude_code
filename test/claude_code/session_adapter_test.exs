defmodule ClaudeCode.SessionAdapterTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Session
  alias ClaudeCode.Test.Factory

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
          msg = Factory.result_message(result: "done")
          ClaudeCode.Adapter.notify_message(state.session, request_id, msg)
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

      # The adapter should have received the config as-is
      adapter_opts = GenServer.call(adapter_pid, :get_opts)
      assert Keyword.get(adapter_opts, :my_key) == "my_value"
      assert Keyword.get(adapter_opts, :another_key) == 42

      GenServer.stop(session)
    end

    test "custom adapter receives config without extra keys injected" do
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

      {:ok, session} = Session.start_link(adapter: {CallerCheckAdapter, [custom: true]})

      state = :sys.get_state(session)
      adapter_opts = GenServer.call(state.adapter_pid, :get_opts)

      assert Keyword.get(adapter_opts, :custom) == true
      # Session merges top-level opts into adapter config so adapters
      # like Adapter.Node can receive :cwd, :model, etc. automatically.
      # Adapter-specific keys take precedence over session defaults.
      assert :custom in Keyword.keys(adapter_opts)

      GenServer.stop(session)
    end
  end

  # ============================================================================
  # Adapter status handling (provisioning → ready / error)
  # ============================================================================

  describe "adapter status handling" do
    defmodule SlowProvisioningAdapter do
      @moduledoc false
      @behaviour ClaudeCode.Adapter

      use GenServer

      alias ClaudeCode.Adapter

      @impl ClaudeCode.Adapter
      def start_link(session, opts), do: GenServer.start_link(__MODULE__, {session, opts})

      @impl ClaudeCode.Adapter
      def send_query(adapter, request_id, prompt, opts) do
        GenServer.cast(adapter, {:query, request_id, prompt, opts})
        :ok
      end

      @impl ClaudeCode.Adapter
      def health(_adapter), do: :healthy

      @impl ClaudeCode.Adapter
      def stop(adapter), do: GenServer.stop(adapter, :normal)

      @impl GenServer
      def init({session, opts}) do
        Process.link(session)
        delay = Keyword.get(opts, :provisioning_delay, 200)
        Adapter.notify_status(session, :provisioning)
        {:ok, %{session: session, delay: delay}, {:continue, :provision}}
      end

      @impl GenServer
      def handle_continue(:provision, state) do
        Process.sleep(state.delay)
        Adapter.notify_status(state.session, :ready)
        {:noreply, state}
      end

      @impl GenServer
      def handle_cast({:query, request_id, _prompt, _opts}, state) do
        msg = Factory.result_message(result: "provisioned response")
        Adapter.notify_message(state.session, request_id, msg)
        {:noreply, state}
      end
    end

    test "queries sent during provisioning are queued and executed after ready" do
      {:ok, session} =
        ClaudeCode.Session.start_link(adapter: {SlowProvisioningAdapter, [provisioning_delay: 200]})

      result =
        session
        |> ClaudeCode.stream("test")
        |> ClaudeCode.Stream.final_text()

      assert result == "provisioned response"

      GenServer.stop(session)
    end

    test "multiple queries during provisioning all get processed" do
      {:ok, session} =
        ClaudeCode.Session.start_link(adapter: {SlowProvisioningAdapter, [provisioning_delay: 200]})

      tasks =
        Enum.map(1..3, fn _i ->
          Task.async(fn ->
            session
            |> ClaudeCode.stream("test")
            |> ClaudeCode.Stream.final_text()
          end)
        end)

      results = Enum.map(tasks, &Task.await(&1, 5000))

      assert Enum.all?(results, &(&1 == "provisioned response"))

      GenServer.stop(session)
    end

    defmodule FailingProvisioningAdapter do
      @moduledoc false
      @behaviour ClaudeCode.Adapter

      use GenServer

      alias ClaudeCode.Adapter

      @impl ClaudeCode.Adapter
      def start_link(session, opts), do: GenServer.start_link(__MODULE__, {session, opts})

      @impl ClaudeCode.Adapter
      def send_query(adapter, request_id, prompt, opts) do
        GenServer.cast(adapter, {:query, request_id, prompt, opts})
        :ok
      end

      @impl ClaudeCode.Adapter
      def health(_adapter), do: :healthy

      @impl ClaudeCode.Adapter
      def stop(adapter), do: GenServer.stop(adapter, :normal)

      @impl GenServer
      def init({session, _opts}) do
        Process.link(session)
        Adapter.notify_status(session, :provisioning)
        {:ok, %{session: session}, {:continue, :provision}}
      end

      @impl GenServer
      def handle_continue(:provision, state) do
        Process.sleep(100)
        Adapter.notify_status(state.session, {:error, :sandbox_unavailable})
        {:noreply, state}
      end

      @impl GenServer
      def handle_cast({:query, _request_id, _prompt, _opts}, state) do
        {:noreply, state}
      end
    end

    test "queued queries fail when provisioning fails" do
      {:ok, session} =
        ClaudeCode.Session.start_link(adapter: {FailingProvisioningAdapter, []})

      thrown =
        session
        |> ClaudeCode.stream("test")
        |> Enum.to_list()
        |> catch_throw()

      assert {:stream_error, {:provisioning_failed, :sandbox_unavailable}} = thrown

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
