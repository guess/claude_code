defmodule ClaudeCode.Adapter.NodeTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Node, as: NodeAdapter

  describe "start_link/2 config validation" do
    test "raises when :node is missing" do
      assert_raise KeyError, ~r/:node/, fn ->
        NodeAdapter.start_link(self(), cwd: "/tmp/test")
      end
    end

    test "raises when :cwd is missing" do
      assert_raise KeyError, ~r/:cwd/, fn ->
        NodeAdapter.start_link(self(), node: :fake@node)
      end
    end

    test "returns error when node is unreachable" do
      result =
        NodeAdapter.start_link(self(),
          node: :nonexistent@nowhere,
          cwd: "/tmp/test",
          connect_timeout: 500
        )

      # Node.connect/1 returns false immediately for unreachable nodes in most
      # environments, yielding {:node_connect_failed, node}. On slow networks
      # where DNS lookup blocks until the timeout, {:connect_timeout, node} may
      # be returned instead.
      assert match?({:error, {:node_connect_failed, :nonexistent@nowhere}}, result) or
               match?({:error, {:connect_timeout, :nonexistent@nowhere}}, result)
    end
  end

  describe "integration with peer node" do
    @describetag :distributed

    setup do
      # Peer nodes start as bare Erlang — pass all code paths so Elixir
      # modules (File, ClaudeCode.Adapter.Port, etc.) are available.
      # OTP 27+ expects args as a list of charlists (one per token).
      args =
        Enum.flat_map(:code.get_path(), fn path -> [~c"-pa", to_charlist(path)] end)

      {:ok, peer, node} =
        :peer.start(%{
          name: :"adapter_test_peer_#{System.unique_integer([:positive])}",
          args: args
        })

      on_exit(fn ->
        try do
          :peer.stop(peer)
        catch
          :exit, _ -> :ok
        end
      end)

      {:ok, node: node, peer: peer}
    end

    test "connects to peer and creates workspace", %{node: node} do
      workspace =
        Path.join(System.tmp_dir!(), "adapter_node_test_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(workspace) end)

      {:ok, adapter_pid} =
        NodeAdapter.start_link(self(),
          node: node,
          cwd: workspace
        )

      # Adapter is running on the remote node
      assert node(adapter_pid) == node

      # Workspace was created
      assert :rpc.call(node, File, :dir?, [workspace]) == true

      NodeAdapter.stop(adapter_pid)
    end

    test "delegates health check to remote adapter", %{node: node} do
      workspace =
        Path.join(System.tmp_dir!(), "adapter_node_health_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(workspace) end)

      {:ok, adapter_pid} =
        NodeAdapter.start_link(self(),
          node: node,
          cwd: workspace
        )

      health = NodeAdapter.health(adapter_pid)
      assert health in [:healthy, :degraded] or match?({:unhealthy, _}, health)

      NodeAdapter.stop(adapter_pid)
    end

    test "session receives EXIT when peer node stops", %{node: node, peer: peer} do
      workspace =
        Path.join(System.tmp_dir!(), "adapter_node_exit_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(workspace) end)

      Process.flag(:trap_exit, true)

      {:ok, adapter_pid} =
        NodeAdapter.start_link(self(),
          node: node,
          cwd: workspace
        )

      :peer.stop(peer)

      assert_receive {:EXIT, ^adapter_pid, :noconnection}, 5_000
    end
  end
end
