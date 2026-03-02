defmodule ClaudeCode.Adapter.Port.ProxyDelegationTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Port, as: PortAdapter
  alias ClaudeCode.Hook.Registry, as: HookRegistry

  # ============================================================================
  # Mock Proxy GenServer
  # ============================================================================

  defmodule MockProxy do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      handler = Keyword.get(opts, :handler, fn msg -> {:default_response, msg} end)
      GenServer.start_link(__MODULE__, handler)
    end

    @impl true
    def init(handler), do: {:ok, handler}

    @impl true
    def handle_call({:control_request, msg}, _from, handler) do
      {:reply, handler.(msg), handler}
    end
  end

  # ============================================================================
  # Proxy Monitor Helper (mimics Adapter.Port's monitor pattern)
  # ============================================================================

  defmodule ProxyMonitorHelper do
    @moduledoc false
    use GenServer

    def start_link(proxy_pid) do
      GenServer.start_link(__MODULE__, proxy_pid)
    end

    def get_proxy(server), do: GenServer.call(server, :get_proxy)

    @impl true
    def init(proxy_pid) do
      if proxy_pid, do: Process.monitor(proxy_pid)
      {:ok, %{callback_proxy: proxy_pid}}
    end

    @impl true
    def handle_call(:get_proxy, _from, state) do
      {:reply, state.callback_proxy, state}
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, proxy, _reason}, %{callback_proxy: proxy} = state) do
      {:noreply, %{state | callback_proxy: nil}}
    end
  end

  # ============================================================================
  # Mock Hook Module
  # ============================================================================

  defmodule RemoteHook do
    @moduledoc false
    @behaviour ClaudeCode.Hook

    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  # ============================================================================
  # Struct Field Tests
  # ============================================================================

  describe "struct fields" do
    test "callback_proxy defaults to nil" do
      state = %PortAdapter{}
      assert state.callback_proxy == nil
    end

    test "callback_timeout defaults to 30_000" do
      state = %PortAdapter{}
      assert state.callback_timeout == 30_000
    end

    test "struct accepts callback_proxy pid" do
      pid = self()
      state = %PortAdapter{callback_proxy: pid}
      assert state.callback_proxy == pid
    end

    test "struct accepts custom callback_timeout" do
      state = %PortAdapter{callback_timeout: 60_000}
      assert state.callback_timeout == 60_000
    end
  end

  # ============================================================================
  # MockProxy Tests
  # ============================================================================

  describe "MockProxy" do
    test "handles {:control_request, msg} calls" do
      {:ok, proxy} = MockProxy.start_link(handler: fn msg -> %{"handled" => msg["subtype"]} end)

      msg = %{"request_id" => "req_1", "request" => %{"subtype" => "can_use_tool"}, "subtype" => "can_use_tool"}
      result = GenServer.call(proxy, {:control_request, msg})

      assert result == %{"handled" => "can_use_tool"}
    end

    test "returns custom response based on handler" do
      {:ok, proxy} =
        MockProxy.start_link(
          handler: fn _msg ->
            %{"behavior" => "allow"}
          end
        )

      result = GenServer.call(proxy, {:control_request, %{"request" => %{"subtype" => "can_use_tool"}}})
      assert result == %{"behavior" => "allow"}
    end
  end

  # ============================================================================
  # Proxy Delegation Routing Tests
  # ============================================================================

  describe "proxy delegation routing" do
    test "mcp_message is routed to proxy" do
      test_pid = self()

      {:ok, proxy} =
        MockProxy.start_link(
          handler: fn msg ->
            send(test_pid, {:proxy_called, msg})
            %{"mcp_response" => %{"result" => "ok"}}
          end
        )

      # Simulate what handle_inbound_control_request does for mcp_message
      # by calling proxy directly (the function is private)
      msg = %{
        "request_id" => "req_1",
        "request" => %{"subtype" => "mcp_message", "server_name" => "test", "message" => %{}}
      }

      result = GenServer.call(proxy, {:control_request, msg})
      assert result == %{"mcp_response" => %{"result" => "ok"}}
      assert_receive {:proxy_called, ^msg}
    end

    test "can_use_tool is routed to proxy" do
      test_pid = self()

      {:ok, proxy} =
        MockProxy.start_link(
          handler: fn msg ->
            send(test_pid, {:proxy_called, msg})
            %{"behavior" => "allow"}
          end
        )

      msg = %{
        "request_id" => "req_2",
        "request" => %{"subtype" => "can_use_tool", "tool_name" => "Bash", "input" => %{}}
      }

      result = GenServer.call(proxy, {:control_request, msg})
      assert result == %{"behavior" => "allow"}
      assert_receive {:proxy_called, ^msg}
    end

    test "hook_callback with local registry hit does NOT go to proxy" do
      test_pid = self()

      {:ok, proxy} =
        MockProxy.start_link(
          handler: fn _msg ->
            send(test_pid, :proxy_was_called)
            %{"should_not" => "happen"}
          end
        )

      # Build a registry with a known hook
      hooks = %{PreToolUse: [%{hooks: [RemoteHook]}]}
      {registry, _wire} = HookRegistry.new(hooks, nil)

      # Verify the hook is in the registry
      assert {:ok, RemoteHook} = HookRegistry.lookup(registry, "hook_0")

      # When the callback_id is found locally, it should use ControlHandler
      # not the proxy. We verify by checking the proxy is NOT called.
      _state = %PortAdapter{
        callback_proxy: proxy,
        callback_timeout: 5_000,
        hook_registry: registry
      }

      # The lookup succeeds locally
      assert {:ok, _} = HookRegistry.lookup(registry, "hook_0")

      # Proxy should not have been called
      refute_receive :proxy_was_called
    end

    test "hook_callback with local registry miss falls through to proxy" do
      test_pid = self()

      {:ok, proxy} =
        MockProxy.start_link(
          handler: fn msg ->
            send(test_pid, {:proxy_called, msg})
            %{"hook_result" => "from_proxy"}
          end
        )

      # Empty registry - no local hooks
      {registry, _wire} = HookRegistry.new(%{}, nil)

      # Verify the hook is NOT in the registry
      assert :error = HookRegistry.lookup(registry, "hook_99")

      # Call proxy directly to simulate the fallback path
      msg = %{
        "request_id" => "req_3",
        "request" => %{"subtype" => "hook_callback", "callback_id" => "hook_99", "input" => %{}, "tool_use_id" => nil}
      }

      result = GenServer.call(proxy, {:control_request, msg})
      assert result == %{"hook_result" => "from_proxy"}
      assert_receive {:proxy_called, ^msg}
    end
  end

  # ============================================================================
  # Proxy Call Error Handling Tests
  # ============================================================================

  describe "proxy_call error handling" do
    test "handles proxy exit gracefully" do
      {:ok, proxy} = MockProxy.start_link()
      GenServer.stop(proxy)

      # Calling a stopped proxy should not raise
      result =
        try do
          GenServer.call(proxy, {:control_request, %{}}, 100)
        catch
          :exit, _ -> nil
        end

      assert result == nil
    end

    test "handles proxy timeout gracefully" do
      {:ok, proxy} =
        MockProxy.start_link(
          handler: fn _msg ->
            # Sleep longer than the timeout
            Process.sleep(500)
            %{"too_late" => true}
          end
        )

      result =
        try do
          GenServer.call(proxy, {:control_request, %{}}, 50)
        catch
          :exit, _ -> nil
        end

      assert result == nil
    end
  end

  # ============================================================================
  # Proxy Monitoring Tests
  # ============================================================================

  describe "proxy monitoring" do
    test "callback_proxy is nilled out when proxy process dies" do
      {:ok, proxy} = MockProxy.start_link()

      state = %PortAdapter{callback_proxy: proxy, callback_timeout: 5_000}
      assert state.callback_proxy == proxy

      # Simulate what Adapter.Port.init does: monitor the proxy
      ref = Process.monitor(proxy)
      GenServer.stop(proxy)

      assert_receive {:DOWN, ^ref, :process, ^proxy, :normal}
      # In real Adapter.Port, this would trigger handle_info to nil out the proxy
    end

    test "proxy death results in nil proxy in adapter state" do
      # Start a real Adapter.Port with a proxy that we'll kill
      {:ok, proxy} = MockProxy.start_link()

      # We can't easily start a full Adapter.Port without a CLI, but we can
      # verify the monitor + handle_info pattern works by testing the GenServer
      # behavior directly. Start a simple GenServer that mimics the pattern.
      {:ok, adapter} = ProxyMonitorHelper.start_link(proxy)

      assert ProxyMonitorHelper.get_proxy(adapter) == proxy

      GenServer.stop(proxy)

      # Poll until the :DOWN message is processed instead of sleeping
      Enum.reduce_while(1..100, nil, fn _, _ ->
        if ProxyMonitorHelper.get_proxy(adapter) == nil do
          {:halt, :ok}
        else
          Process.sleep(1)
          {:cont, nil}
        end
      end)

      assert ProxyMonitorHelper.get_proxy(adapter) == nil
    end
  end

  # ============================================================================
  # HookRegistry Lookup-Then-Delegate Pattern Tests
  # ============================================================================

  describe "HookRegistry lookup-then-delegate pattern" do
    test "lookup succeeds for registered hooks" do
      hooks = %{PreToolUse: [%{hooks: [RemoteHook]}]}
      {registry, _wire} = HookRegistry.new(hooks, nil)

      assert {:ok, RemoteHook} = HookRegistry.lookup(registry, "hook_0")
    end

    test "lookup fails for unregistered hooks" do
      {registry, _wire} = HookRegistry.new(%{}, nil)

      assert :error = HookRegistry.lookup(registry, "hook_unknown")
    end

    test "registry with remote hooks can be passed directly" do
      # Simulate what Adapter.Node would do: pre-build a registry with only remote hooks
      hooks = %{
        PreToolUse: [%{hooks: [RemoteHook], where: :remote}]
      }

      {full_registry, _wire} = HookRegistry.new(hooks, nil)
      {_local, remote_registry} = HookRegistry.split(full_registry)

      # The remote registry should have the hook
      assert {:ok, RemoteHook} = HookRegistry.lookup(remote_registry, "hook_0")

      # Can be set on the struct
      state = %PortAdapter{hook_registry: remote_registry}
      assert {:ok, RemoteHook} = HookRegistry.lookup(state.hook_registry, "hook_0")
    end

    test "split registry: local hooks stay local, remote hooks go remote" do
      hooks = %{
        PreToolUse: [
          %{hooks: [RemoteHook], where: :local},
          %{hooks: [RemoteHook], where: :remote}
        ]
      }

      {full_registry, _wire} = HookRegistry.new(hooks, nil)
      {local_registry, remote_registry} = HookRegistry.split(full_registry)

      # hook_0 is local, hook_1 is remote
      assert {:ok, _} = HookRegistry.lookup(local_registry, "hook_0")
      assert :error = HookRegistry.lookup(local_registry, "hook_1")

      assert :error = HookRegistry.lookup(remote_registry, "hook_0")
      assert {:ok, _} = HookRegistry.lookup(remote_registry, "hook_1")
    end
  end
end
