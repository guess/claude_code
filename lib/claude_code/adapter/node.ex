defmodule ClaudeCode.Adapter.Node do
  @moduledoc """
  Distributed adapter that runs `Adapter.Port` on a remote BEAM node.

  Connects to a remote node via Erlang distribution, creates a workspace
  directory, and starts `Adapter.Port` there. After startup, Session talks
  directly to the remote adapter — `GenServer.call/2` and `send/2` work
  transparently across connected BEAM nodes.

  ## Usage

      {:ok, session} = ClaudeCode.Session.start_link(
        cwd: "/workspaces/tenant-123",
        model: "claude-sonnet-4-20250514",
        adapter: {ClaudeCode.Adapter.Node, [
          node: :"claude@gpu-server"
        ]}
      )

  Session-level options (`:model`, `:cwd`, `:system_prompt`, etc.) are passed
  to `start_link/1` as usual. They are merged into the adapter config
  automatically. The adapter tuple only needs Node-specific options (`:node`,
  `:cookie`, `:connect_timeout`, `:callback_timeout`) which are consumed by
  this module and not forwarded to the remote `Adapter.Port`.

  ## In-Process MCP Tools and Hooks

  MCP tools (defined with `ClaudeCode.MCP.Server`) always execute on the local
  node — they are routed through a `CallbackProxy` GenServer that lives on your
  app server.

  Hooks support a `:where` option on matcher configs:

    - `:local` (default) — runs on your app server via the proxy
    - `:remote` — runs on the sandbox server in the remote `Adapter.Port`

  The `can_use_tool` callback always runs locally.

  ## Failure Handling

  The distributed link between Session and the remote adapter fires on
  nodedown. Session receives `{:EXIT, pid, :noconnection}` and handles it
  like any adapter crash. No automatic reconnection — create a new Session
  to reconnect.
  """

  @behaviour ClaudeCode.Adapter

  alias ClaudeCode.Adapter.Node.CallbackProxy
  alias ClaudeCode.Adapter.Port, as: AdapterPort
  alias ClaudeCode.Hook.Registry, as: HookRegistry

  @node_opts [:node, :cookie, :connect_timeout, :callback_timeout]

  @impl ClaudeCode.Adapter
  def start_link(session, config) do
    node = Keyword.fetch!(config, :node)
    cookie = Keyword.get(config, :cookie)
    cwd = Keyword.fetch!(config, :cwd)
    timeout = Keyword.get(config, :connect_timeout, 5_000)
    callback_timeout = Keyword.get(config, :callback_timeout, 30_000)

    if cookie, do: Node.set_cookie(node, cookie)

    with :ok <- connect_node(node, timeout),
         :ok <- ensure_workspace(node, cwd) do
      hooks_map = Keyword.get(config, :hooks)
      can_use_tool = Keyword.get(config, :can_use_tool)
      mcp_servers = Keyword.get(config, :mcp_servers)

      # Build full registry so we can partition by locality
      {full_registry, _wire} = HookRegistry.new(hooks_map, can_use_tool)
      {local_registry, remote_registry} = HookRegistry.split(full_registry)

      # Build stub sdk_mcp_servers map: names only (nil values), since the
      # actual modules live on the local node and execute via the proxy.
      # Port reads Map.keys/1 for the initialize handshake, and nil values
      # produce clean "server not found" errors if the proxy is unavailable.
      local_sdk_servers = AdapterPort.extract_sdk_mcp_servers(mcp_servers: mcp_servers)

      stub_sdk_servers =
        if local_sdk_servers == %{},
          do: %{},
          else: Map.new(local_sdk_servers, fn {name, _} -> {name, nil} end)

      # Start proxy on LOCAL node if there are local callbacks
      proxy =
        if has_local_callbacks?(local_registry, mcp_servers) do
          {:ok, pid} =
            CallbackProxy.start_link(
              mcp_servers: mcp_servers,
              hook_registry: local_registry
            )

          pid
        end

      # Build config for the REMOTE Adapter.Port.
      # :hooks stays so Port can build the wire format for the initialize handshake.
      # :mcp_servers is dropped because modules aren't available on the remote node;
      # :sdk_mcp_servers stub provides just the names Port needs.
      adapter_opts =
        config
        |> Keyword.drop(@node_opts ++ [:mcp_servers])
        |> Keyword.put(:hook_registry, remote_registry)
        |> Keyword.put(:sdk_mcp_servers, stub_sdk_servers)
        |> Keyword.put(:can_use_tool, if(can_use_tool, do: :proxied))
        |> Keyword.put(:callback_proxy, proxy)
        |> Keyword.put(:callback_timeout, callback_timeout)

      # Use GenServer.start (not start_link) via RPC to avoid linking the
      # adapter to the ephemeral RPC handler process.  Adapter.Port.init/1
      # already calls Process.link(session), which is the link we actually want.
      case :rpc.call(node, GenServer, :start, [ClaudeCode.Adapter.Port, {session, adapter_opts}]) do
        {:ok, pid} -> {:ok, pid}
        {:error, _} = err -> err
        {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
      end
    end
  end

  @impl ClaudeCode.Adapter
  defdelegate send_query(adapter, request_id, prompt, opts), to: ClaudeCode.Adapter.Port

  @impl ClaudeCode.Adapter
  defdelegate health(adapter), to: ClaudeCode.Adapter.Port

  @impl ClaudeCode.Adapter
  defdelegate stop(adapter), to: ClaudeCode.Adapter.Port

  @impl ClaudeCode.Adapter
  defdelegate interrupt(adapter), to: ClaudeCode.Adapter.Port

  @impl ClaudeCode.Adapter
  defdelegate send_control_request(adapter, subtype, params), to: ClaudeCode.Adapter.Port

  @impl ClaudeCode.Adapter
  defdelegate get_server_info(adapter), to: ClaudeCode.Adapter.Port

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp has_local_callbacks?(local_registry, mcp_servers) do
    has_mcp = mcp_servers != nil and mcp_servers != %{}
    has_hooks = map_size(local_registry.callbacks) > 0
    has_can_use_tool = local_registry.can_use_tool != nil
    has_mcp or has_hooks or has_can_use_tool
  end

  defp connect_node(node, timeout) do
    task = Task.async(fn -> Node.connect(node) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, {:node_connect_failed, node}}
      {:ok, :ignored} -> {:error, {:node_connect_failed, node}}
      nil -> {:error, {:connect_timeout, node}}
    end
  end

  defp ensure_workspace(node, path) do
    case :rpc.call(node, File, :mkdir_p, [path]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:workspace_failed, reason}}
      {:badrpc, reason} -> {:error, {:rpc_failed, reason}}
    end
  end
end
