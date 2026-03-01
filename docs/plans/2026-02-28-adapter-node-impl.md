# Adapter.Node + Adapter Rename Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename existing adapters by transport (Local→Port, Remote→WebSocket), then add `Adapter.Node` for distributed sessions via BEAM.

**Architecture:** `Adapter.Node` is a stateless factory (~55 lines) that connects to a remote BEAM node, creates a workspace directory via RPC, starts `Adapter.Port` there, and returns the remote PID. Session talks directly to the remote adapter — `GenServer.call/2` and `send/2` work transparently across connected nodes. No protocol layer, no sidecar.

**Tech Stack:** Erlang distribution (stdlib), `:peer` module (OTP 25+) for testing.

**Design doc:** `docs/plans/2026-02-28-adapter-node-design.md`

---

## Phase 1: Rename Adapter.Local → Adapter.Port

Rename files, modules, and all references. No behavior changes.

### Task 1: Rename Adapter.Local module and files

**Files:**
- Rename: `lib/claude_code/adapter/local.ex` → `lib/claude_code/adapter/port.ex`
- Rename: `lib/claude_code/adapter/local/` → `lib/claude_code/adapter/port/`
  - `local/resolver.ex` → `port/resolver.ex`
  - `local/installer.ex` → `port/installer.ex`

**Step 1: Move the files**

```bash
git mv lib/claude_code/adapter/local.ex lib/claude_code/adapter/port.ex
git mv lib/claude_code/adapter/local lib/claude_code/adapter/port
```

**Step 2: Update module names in moved files**

In `lib/claude_code/adapter/port.ex`:
- `defmodule ClaudeCode.Adapter.Local` → `defmodule ClaudeCode.Adapter.Port`
- `alias ClaudeCode.Adapter.Local.Installer` → `alias ClaudeCode.Adapter.Port.Installer`
- `alias ClaudeCode.Adapter.Local.Resolver` → `alias ClaudeCode.Adapter.Port.Resolver`

In `lib/claude_code/adapter/port/resolver.ex`:
- `defmodule ClaudeCode.Adapter.Local.Resolver` → `defmodule ClaudeCode.Adapter.Port.Resolver`
- `alias ClaudeCode.Adapter.Local.Installer` → `alias ClaudeCode.Adapter.Port.Installer`
- Update all `ClaudeCode.Adapter.Local.Resolver` in docs/examples

In `lib/claude_code/adapter/port/installer.ex`:
- `defmodule ClaudeCode.Adapter.Local.Installer` → `defmodule ClaudeCode.Adapter.Port.Installer`
- Update all `ClaudeCode.Adapter.Local.Installer` in docs/examples
- Update `ClaudeCode.Adapter.Local.Resolver.find_binary/1` doc reference

**Step 3: Update all references in lib/**

These files reference `Adapter.Local`:

- `lib/claude_code/session.ex` — Line 281: `{ClaudeCode.Adapter.Local, opts}` → `{ClaudeCode.Adapter.Port, opts}`. Line 9 doc reference.
- `lib/claude_code/adapter.ex` — Lines 36, 40: doc references to `Adapter.Local`
- `lib/claude_code/cli/command.ex` — Line 9: doc reference
- `lib/mix/tasks/claude_code.install.ex` — `alias ClaudeCode.Adapter.Local.Installer` → `alias ClaudeCode.Adapter.Port.Installer`
- `lib/mix/tasks/claude_code.uninstall.ex` — same alias update
- `lib/mix/tasks/claude_code.path.ex` — `alias ClaudeCode.Adapter.Local.Resolver` → `alias ClaudeCode.Adapter.Port.Resolver`

**Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation, zero warnings.

### Task 2: Rename Adapter.Local test files

**Files:**
- Rename: `test/claude_code/adapter/local_test.exs` → `test/claude_code/adapter/port_test.exs`
- Rename: `test/claude_code/adapter/local_integration_test.exs` → `test/claude_code/adapter/port_integration_test.exs`
- Rename: `test/claude_code/adapter/local/` → `test/claude_code/adapter/port/`
  - `local/installer_test.exs` → `port/installer_test.exs`
  - `local/resolver_test.exs` → `port/resolver_test.exs`
  - `local/mcp_routing_test.exs` → `port/mcp_routing_test.exs`

**Step 1: Move the test files**

```bash
git mv test/claude_code/adapter/local_test.exs test/claude_code/adapter/port_test.exs
git mv test/claude_code/adapter/local_integration_test.exs test/claude_code/adapter/port_integration_test.exs
git mv test/claude_code/adapter/local test/claude_code/adapter/port
```

**Step 2: Update module names and aliases in all moved test files**

In `test/claude_code/adapter/port_test.exs`:
- `defmodule ClaudeCode.Adapter.LocalTest` → `defmodule ClaudeCode.Adapter.PortTest`
- `alias ClaudeCode.Adapter.Local` → `alias ClaudeCode.Adapter.Port`
- All `Local.` calls → `Port.` calls
- All string references like `"Adapter.Local exports"` in test descriptions

In `test/claude_code/adapter/port_integration_test.exs`:
- `defmodule ClaudeCode.Adapter.LocalIntegrationTest` → `defmodule ClaudeCode.Adapter.PortIntegrationTest`

In `test/claude_code/adapter/port/installer_test.exs`:
- `defmodule ClaudeCode.Adapter.Local.InstallerTest` → `defmodule ClaudeCode.Adapter.Port.InstallerTest`
- `alias ClaudeCode.Adapter.Local.Installer` → `alias ClaudeCode.Adapter.Port.Installer`

In `test/claude_code/adapter/port/resolver_test.exs`:
- `defmodule ClaudeCode.Adapter.Local.ResolverTest` → `defmodule ClaudeCode.Adapter.Port.ResolverTest`
- `alias ClaudeCode.Adapter.Local.Resolver` → `alias ClaudeCode.Adapter.Port.Resolver`

In `test/claude_code/adapter/port/mcp_routing_test.exs`:
- `defmodule ClaudeCode.Adapter.Local.MCPRoutingTest` → `defmodule ClaudeCode.Adapter.Port.MCPRoutingTest`
- `alias ClaudeCode.Adapter.Local` → `alias ClaudeCode.Adapter.Port`

Also update comment references in `test/claude_code/session_test.exs`:
- `"simulating what Adapter.Local would do"` → `"simulating what Adapter.Port would do"`
- `"simulating what Adapter.Remote would do"` → `"simulating what Adapter.WebSocket would do"`

Also update aliases in mix task tests:
- `test/mix/tasks/claude_code_install_test.exs` — `alias ClaudeCode.Adapter.Local.Installer` → `alias ClaudeCode.Adapter.Port.Installer`
- `test/mix/tasks/claude_code_uninstall_test.exs` — same

**Step 3: Run the full test suite**

Run: `mix test`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename Adapter.Local → Adapter.Port"
```

---

## Phase 2: Rename Adapter.Remote → Adapter.WebSocket

### Task 3: Rename Adapter.Remote module and files

**Files:**
- Rename: `lib/claude_code/adapter/remote.ex` → `lib/claude_code/adapter/websocket.ex`
- Rename: `test/claude_code/adapter/remote_test.exs` → `test/claude_code/adapter/websocket_test.exs`
- Rename: `test/claude_code/adapter/remote_integration_test.exs` → `test/claude_code/adapter/websocket_integration_test.exs`

**Step 1: Move the files**

```bash
git mv lib/claude_code/adapter/remote.ex lib/claude_code/adapter/websocket.ex
git mv test/claude_code/adapter/remote_test.exs test/claude_code/adapter/websocket_test.exs
git mv test/claude_code/adapter/remote_integration_test.exs test/claude_code/adapter/websocket_integration_test.exs
```

**Step 2: Update module names**

In `lib/claude_code/adapter/websocket.ex`:
- `defmodule ClaudeCode.Adapter.Remote` → `defmodule ClaudeCode.Adapter.WebSocket`
- Update all `Adapter.Remote` references in module docs
- Update `Adapter.Local` references in docs → `Adapter.Port` (if any remain)

In `test/claude_code/adapter/websocket_test.exs`:
- `defmodule ClaudeCode.Adapter.RemoteTest` → `defmodule ClaudeCode.Adapter.WebSocketTest`
- `alias ClaudeCode.Adapter.Remote` → `alias ClaudeCode.Adapter.WebSocket`
- All `Remote.` calls → `WebSocket.` calls

In `test/claude_code/adapter/websocket_integration_test.exs`:
- `defmodule ClaudeCode.Adapter.RemoteIntegrationTest` → `defmodule ClaudeCode.Adapter.WebSocketIntegrationTest`
- `alias ClaudeCode.Adapter.Remote` → `alias ClaudeCode.Adapter.WebSocket`
- All `Remote.` calls → `WebSocket.` calls

**Step 3: Update references in sidecar**

- `sidecar/test/claude_code/sidecar/end_to_end_test.exs` — `Remote` → `WebSocket` alias and references

**Step 4: Update session_test.exs comment** (if not already done in Task 2)

**Step 5: Run tests and verify**

Run: `mix test`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename Adapter.Remote → Adapter.WebSocket"
```

---

## Phase 3: Update documentation for renames

### Task 4: Update CLAUDE.md and project docs

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update CLAUDE.md architecture section**

Replace references to the old names:

- `Adapter.Local (Port)` → `Adapter.Port`
- `Adapter.Local.Resolver` → `Adapter.Port.Resolver`
- `Adapter.Local.Installer` → `Adapter.Port.Installer`
- `ClaudeCode.Adapter.Local` → `ClaudeCode.Adapter.Port`
- File paths: `adapter/local.ex` → `adapter/port.ex`, `adapter/local/` → `adapter/port/`

Do NOT update old plan docs in `docs/plans/` — they are historical records.

**Step 2: Run quality checks**

Run: `mix quality`
Expected: All checks pass (compile, format, credo, dialyzer).

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for adapter rename"
```

---

## Phase 4: Implement Adapter.Node

### Task 5: Write failing tests for Adapter.Node config validation

**Files:**
- Create: `test/claude_code/adapter/node_test.exs`

**Step 1: Write the tests**

```elixir
defmodule ClaudeCode.Adapter.NodeTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Node, as: NodeAdapter

  describe "start_link/2 config validation" do
    test "returns error when :node is missing" do
      assert_raise KeyError, ~r/:node/, fn ->
        NodeAdapter.start_link(self(), [workspace_path: "/tmp/test"])
      end
    end

    test "returns error when :workspace_path is missing" do
      assert_raise KeyError, ~r/:workspace_path/, fn ->
        NodeAdapter.start_link(self(), [node: :"fake@node"])
      end
    end

    test "returns error when node is unreachable" do
      result = NodeAdapter.start_link(self(), [
        node: :"nonexistent@nowhere",
        workspace_path: "/tmp/test",
        connect_timeout: 500
      ])

      assert {:error, {:connect_timeout, :"nonexistent@nowhere"}} = result
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/adapter/node_test.exs`
Expected: FAIL — module `ClaudeCode.Adapter.Node` not found.

### Task 6: Implement Adapter.Node

**Files:**
- Create: `lib/claude_code/adapter/node.ex`

**Step 1: Write the implementation**

```elixir
defmodule ClaudeCode.Adapter.Node do
  @moduledoc """
  Distributed adapter that runs Adapter.Port on a remote BEAM node.

  Connects to a remote node via Erlang distribution, creates a workspace
  directory, and starts `Adapter.Port` there. After startup, Session talks
  directly to the remote adapter — `GenServer.call/2` and `send/2` work
  transparently across connected BEAM nodes.

  ## Usage

      {:ok, session} = ClaudeCode.Session.start_link(
        adapter: {ClaudeCode.Adapter.Node, [
          node: :"claude@gpu-server",
          workspace_path: "/workspaces/tenant-123",
          model: "claude-sonnet-4-20250514"
        ]}
      )

  All standard `Adapter.Port` options are forwarded to the remote adapter.
  Node-specific options (`:node`, `:cookie`, `:workspace_path`, `:connect_timeout`)
  are consumed by this module and not forwarded.

  ## Failure Handling

  The distributed link between Session and the remote adapter fires on nodedown.
  Session receives `{:EXIT, pid, :noconnection}` and handles it like any adapter
  crash. No automatic reconnection — create a new Session to reconnect.
  """

  @behaviour ClaudeCode.Adapter

  @node_opts [:node, :cookie, :workspace_path, :connect_timeout]

  @impl ClaudeCode.Adapter
  def start_link(session, config) do
    node = Keyword.fetch!(config, :node)
    cookie = Keyword.get(config, :cookie)
    workspace = Keyword.fetch!(config, :workspace_path)
    timeout = Keyword.get(config, :connect_timeout, 5_000)

    if cookie, do: Node.set_cookie(node, cookie)

    with :ok <- connect_node(node, timeout),
         :ok <- ensure_workspace(node, workspace) do
      adapter_opts =
        config
        |> Keyword.drop(@node_opts)
        |> Keyword.put(:cwd, workspace)

      case :rpc.call(node, ClaudeCode.Adapter.Port, :start_link, [session, adapter_opts]) do
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

  # ============================================================================
  # Private
  # ============================================================================

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
```

**Step 2: Run the config validation tests**

Run: `mix test test/claude_code/adapter/node_test.exs`
Expected: All 3 tests pass.

**Step 3: Commit**

```bash
git add lib/claude_code/adapter/node.ex test/claude_code/adapter/node_test.exs
git commit -m "feat: add Adapter.Node — distributed sessions via BEAM"
```

### Task 7: Write integration tests using :peer

**Files:**
- Modify: `test/claude_code/adapter/node_test.exs`

These tests start a real peer BEAM node with `:peer.start/1`, then exercise the full adapter lifecycle. The peer node needs access to the compiled modules (they inherit the code path).

**Step 1: Add peer-based integration tests**

Append to `test/claude_code/adapter/node_test.exs`:

```elixir
  describe "integration with peer node" do
    @describetag :distributed

    setup do
      # Start a peer node that shares our code path
      {:ok, peer, node} = :peer.start(%{name: :adapter_test_peer})
      on_exit(fn -> :peer.stop(peer) end)
      {:ok, node: node, peer: peer}
    end

    test "connects to peer and creates workspace", %{node: node} do
      workspace = Path.join(System.tmp_dir!(), "adapter_node_test_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(workspace) end)

      session = self()

      {:ok, adapter_pid} =
        NodeAdapter.start_link(session, [
          node: node,
          workspace_path: workspace
        ])

      # Adapter is running on the remote node
      assert Elixir.Node.node(adapter_pid) == node

      # Workspace was created on the remote node
      assert :rpc.call(node, File, :dir?, [workspace]) == true

      # Clean up
      NodeAdapter.stop(adapter_pid)
    end

    test "returns error for workspace creation failure", %{node: node} do
      # /nonexistent/path should fail mkdir_p on most systems
      result = NodeAdapter.start_link(self(), [
        node: node,
        workspace_path: "/nonexistent_root_path/should/fail"
      ])

      assert {:error, {:workspace_failed, _reason}} = result
    end

    test "delegates health check to remote adapter", %{node: node} do
      workspace = Path.join(System.tmp_dir!(), "adapter_node_health_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(workspace) end)

      session = self()

      {:ok, adapter_pid} =
        NodeAdapter.start_link(session, [
          node: node,
          workspace_path: workspace
        ])

      # Health check works across nodes
      # Adapter.Port reports :healthy or status depending on CLI availability
      health = NodeAdapter.health(adapter_pid)
      assert health in [:healthy, :degraded] or match?({:unhealthy, _}, health)

      NodeAdapter.stop(adapter_pid)
    end

    test "session receives EXIT when peer node stops", %{node: node, peer: peer} do
      workspace = Path.join(System.tmp_dir!(), "adapter_node_exit_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(workspace) end)

      Process.flag(:trap_exit, true)
      session = self()

      {:ok, adapter_pid} =
        NodeAdapter.start_link(session, [
          node: node,
          workspace_path: workspace
        ])

      # Stop the peer node
      :peer.stop(peer)

      # Session (self) should receive EXIT from the distributed link
      assert_receive {:EXIT, ^adapter_pid, :noconnection}, 5_000
    end
  end
```

**Step 2: Run integration tests**

Run: `mix test test/claude_code/adapter/node_test.exs --include distributed`
Expected: All tests pass. The `:distributed` tag lets you skip these in fast runs.

**Step 3: Verify the workspace failure test path**

The `/nonexistent_root_path/should/fail` test may behave differently on different OSes. If it passes unexpectedly (some systems allow root to create anything), adjust to a known-bad path or check that the error tuple is returned.

**Step 4: Commit**

```bash
git add test/claude_code/adapter/node_test.exs
git commit -m "test: add peer-based integration tests for Adapter.Node"
```

### Task 8: Run full quality checks

**Step 1: Run the full quality suite**

Run: `mix quality`
Expected: All checks pass (compile --warnings-as-errors, format, credo --strict, dialyzer).

**Step 2: Fix any issues**

If `mix format` needs changes, run `mix format` and re-check.
If credo or dialyzer report issues, fix them in the adapter module.

**Step 3: Run the full test suite**

Run: `mix test`
Expected: All tests pass (both old and new).

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: address quality check findings"
```

---

## Phase 5: Final documentation

### Task 9: Update CLAUDE.md with Adapter.Node

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Adapter.Node to the architecture section**

In the "Architecture" section, update the three-layer description to mention `Adapter.Node`:

```
1. **Adapter-agnostic** — Session, Stream, Options (validation), Types, Message/Content structs
2. **CLI protocol** — CLI.Command (flags), CLI.Input (stdin), CLI.Parser (JSON parsing)
3. **Adapters** — Adapter.Port (local CLI via Port), Adapter.WebSocket (remote via WS), Adapter.Node (remote via BEAM distribution), Adapter.Test (mock)
```

Add to the key modules list:
```
- **ClaudeCode.Adapter.Node** - Distributed adapter that starts Adapter.Port on a remote BEAM node
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Adapter.Node to CLAUDE.md"
```
