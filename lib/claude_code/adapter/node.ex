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
  `:cookie`, `:connect_timeout`) which are consumed by this module and not
  forwarded to the remote `Adapter.Port`.

  ## Failure Handling

  The distributed link between Session and the remote adapter fires on
  nodedown. Session receives `{:EXIT, pid, :noconnection}` and handles it
  like any adapter crash. No automatic reconnection — create a new Session
  to reconnect.
  """

  @behaviour ClaudeCode.Adapter

  @node_opts [:node, :cookie, :connect_timeout]

  @impl ClaudeCode.Adapter
  def start_link(session, config) do
    node = Keyword.fetch!(config, :node)
    cookie = Keyword.get(config, :cookie)
    cwd = Keyword.fetch!(config, :cwd)
    timeout = Keyword.get(config, :connect_timeout, 5_000)

    if cookie, do: Node.set_cookie(node, cookie)

    with :ok <- connect_node(node, timeout),
         :ok <- ensure_workspace(node, cwd) do
      adapter_opts = Keyword.drop(config, @node_opts)

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
