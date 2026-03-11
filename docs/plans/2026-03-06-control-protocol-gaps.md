# Control Protocol Gaps Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement all missing control protocol request builders, inbound handlers, and wire the initialize response into typed structs.

**Architecture:** Each control request follows a 3-layer pattern: `Control` module builds JSON, `Adapter.Port` dispatches via `build_control_json/3`, and `ClaudeCode` exposes the public API. Inbound requests from CLI are handled in `Adapter.Port.handle_inbound_control_request/2`. Five types in the union (`McpAuthenticate`, `McpClearAuth`, `McpOAuthCallbackUrl`, `RemoteControl`, `SetProactive`) have no type definitions in the captured TS `.d.ts` — they're referenced only in the `SDKControlRequestInner` union. These are excluded from this plan and will be implemented when upstream definitions are published.

**Tech Stack:** Elixir, Jason, ExUnit

**Reference files:**
- TS SDK types: `.claude/skills/cli-sync/captured/ts-sdk-types.d.ts`
- Gap analysis: `.claude/skills/cli-sync/references/type-mapping.md`
- Existing builders: `lib/claude_code/cli/control.ex`
- Existing tests: `test/claude_code/cli/control_test.exs`
- Adapter dispatch: `lib/claude_code/adapter/port.ex` (see `build_control_json/3` at line ~716)
- Public API: `lib/claude_code.ex`
- Existing structs: `lib/claude_code/model_info.ex`, `lib/claude_code/agent_info.ex`, `lib/claude_code/account_info.ex`

---

## Phase 1: Outbound Request Builders (Control module + tests)

All new builders follow the exact same pattern as existing ones: call `encode_control_request/2` with a map matching the TS SDK's wire format. Each task adds the builder to `Control`, a test to `ControlTest`, and updates the `@moduledoc` list.

### Task 1: `mcp_set_servers_request/2`

TS SDK: `SDKControlMcpSetServersRequest { subtype: 'mcp_set_servers', servers: Record<string, McpServerConfig> }`

**Files:**
- Modify: `lib/claude_code/cli/control.ex`
- Modify: `test/claude_code/cli/control_test.exs`

**Step 1: Write the failing test**

Add to `test/claude_code/cli/control_test.exs`:

```elixir
describe "mcp_set_servers_request/2" do
  test "builds mcp_set_servers request JSON" do
    servers = %{
      "my-tools" => %{"type" => "stdio", "command" => "npx", "args" => ["-y", "my-tools"]},
      "db" => %{"type" => "sse", "url" => "http://localhost:3001/sse"}
    }

    json = Control.mcp_set_servers_request("req_1_abc", servers)
    decoded = Jason.decode!(json)

    assert decoded["type"] == "control_request"
    assert decoded["request_id"] == "req_1_abc"
    assert decoded["request"]["subtype"] == "mcp_set_servers"
    assert decoded["request"]["servers"] == servers
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/cli/control_test.exs --seed 0 2>&1 | tail -5`
Expected: FAIL — `Control.mcp_set_servers_request/2 is undefined`

**Step 3: Write implementation**

Add to `lib/claude_code/cli/control.ex` after `mcp_toggle_request/3`:

```elixir
@doc """
Builds an mcp_set_servers control request JSON string.

Replaces the set of dynamically managed MCP servers.

## Parameters

  * `request_id` - Unique request identifier
  * `servers` - Map of server name to server config (stdio, sse, http)

"""
@spec mcp_set_servers_request(String.t(), map()) :: String.t()
def mcp_set_servers_request(request_id, servers) do
  encode_control_request(request_id, %{subtype: "mcp_set_servers", servers: servers})
end
```

Also update the `@moduledoc` list to include `mcp_set_servers_request/2`.

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/cli/control_test.exs --seed 0 2>&1 | tail -5`
Expected: PASS

**Step 5: Commit**

```
git add lib/claude_code/cli/control.ex test/claude_code/cli/control_test.exs
git commit -m "feat: add mcp_set_servers control request builder"
```

---

### Task 2: SKIPPED — `mcp_message_request/3`

`SDKControlMcpMessageRequest` has a full type definition but no public method on the TS SDK `Query` interface. It's internal plumbing for SDK-side MCP transport. Deferred until the TS SDK exposes it publicly.

---

### Task 3: SKIPPED — `apply_flag_settings_request/2`

`SDKControlApplyFlagSettingsRequest` has a full type definition but no public method on the TS SDK `Query` interface. It's internal settings plumbing. Deferred until the TS SDK exposes it publicly.

---

### Task 4: SKIPPED — `get_settings_request/1`

`SDKControlGetSettingsRequest` has a full type definition but no public method on the TS SDK `Query` interface. It's internal settings plumbing. Deferred until the TS SDK exposes it publicly.

---

### Task 5: SKIPPED — `elicitation_response/3`

Elicitation is inbound (CLI → SDK), not outbound. Handled in Phase 3.

---

### Task 6: SKIPPED — Undocumented request builders

Five types (`McpAuthenticate`, `McpClearAuth`, `McpOAuthCallbackUrl`, `RemoteControl`, `SetProactive`) appear in the `SDKControlRequestInner` union but have no type definitions in the TS SDK `.d.ts`. Deferred until upstream publishes full definitions.

---

### Task 7: Update Control moduledoc

**Files:**
- Modify: `lib/claude_code/cli/control.ex`

**Step 1:** Update the `@moduledoc` list in `lib/claude_code/cli/control.ex:21-29` to include all new builders:

```
    * `mcp_set_servers_request/2` — Replace dynamic MCP servers
```

**Step 2:** Run `mix quality` to verify no issues.

**Step 3: Commit**

```
git commit -am "docs: update Control moduledoc with new builders"
```

---

## Phase 2: Adapter Dispatch + Public API

Wire the new builders through `Adapter.Port.build_control_json/3` and expose them in `ClaudeCode`.

### Task 8: Adapter dispatch for new outbound requests

**Files:**
- Modify: `lib/claude_code/adapter/port.ex` (~line 716-758)

**Step 1:** Add `build_control_json` clauses for each new subtype, before the catch-all at line 756:

```elixir
defp build_control_json(:mcp_set_servers, request_id, %{servers: servers}) do
  Control.mcp_set_servers_request(request_id, servers)
end

```

**Step 2:** Run existing tests to verify no regressions:

Run: `mix test test/claude_code/adapter/port_test.exs --seed 0 2>&1 | tail -5`

**Step 3: Commit**

```
git commit -am "feat: add adapter dispatch for new control request types"
```

---

### Task 9: Public API functions in `ClaudeCode`

**Files:**
- Modify: `lib/claude_code.ex`

**Step 1:** Add public functions after the existing control API functions (after `set_max_thinking_tokens`). Follow the exact pattern of existing functions like `mcp_toggle/3`:

```elixir
@doc """
Replaces the set of dynamically managed MCP servers.

## Examples

    {:ok, _} = ClaudeCode.mcp_set_servers(session, %{"tools" => %{"type" => "stdio", "command" => "npx"}})
"""
@spec mcp_set_servers(session(), map()) :: {:ok, map()} | {:error, term()}
def mcp_set_servers(session, servers) do
  GenServer.call(session, {:control, :mcp_set_servers, %{servers: servers}})
end

```

**Step 2:** Run `mix quality` to verify compilation and formatting.

**Step 3: Commit**

```
git commit -am "feat: add public API for new control request types"
```

---

## Phase 3: Inbound Request Handling

### Task 10: Handle inbound `elicitation` control requests

The CLI sends `{ subtype: 'elicitation', mcp_server_name, message, mode?, url?, elicitation_id?, requested_schema? }` when an MCP server needs user input. The SDK should forward this to the session and allow the user to respond.

**Files:**
- Modify: `lib/claude_code/adapter/port.ex` (~line 631, `handle_inbound_control_request/2` fallback)

Currently the fallback clause at line 631 responds with `error_response("Not implemented: #{subtype}")`. This already handles unknown subtypes gracefully. When the CLI sends an `elicitation` request, it gets an error response, and the CLI continues.

**Decision:** For now, add logging for the `elicitation` subtype specifically so we know when it fires. A full implementation (with user callback) requires a new option and is a larger feature.

**Step 1:** Add a specific clause in `handle_inbound_control_request/2` (the non-proxy version at ~line 631) before the catch-all:

```elixir
# In the non-proxy handle_inbound_control_request, add before the catch-all:
"elicitation" ->
  Logger.info("Received MCP elicitation request (not yet implemented): #{inspect(request)}")
  json = Control.error_response(request_id, "Elicitation not implemented")
  if state.port, do: Port.command(state.port, json <> "\n")
  state
```

**Step 2:** Also add the same clause in the proxy version (~line 590) for the `handle_inbound_control_request/2` that delegates to callback_proxy. The proxy already has a catch-all that sends "Not implemented" — this is fine for now.

**Step 3:** Run tests, commit.

```
git commit -am "feat: log inbound elicitation requests (not yet implemented)"
```

---

### Task 11: Handle inbound `control_cancel_request`

TS SDK: `SDKControlCancelRequest { type: 'control_cancel_request', request_id: string }` — Note: this has `type: 'control_cancel_request'`, NOT `type: 'control_request'`. It's a distinct message type.

**Files:**
- Modify: `lib/claude_code/cli/control.ex` — update `classify/1`
- Modify: `test/claude_code/cli/control_test.exs`
- Modify: `lib/claude_code/adapter/port.ex` — handle in message dispatch

**Step 1: Write failing test**

```elixir
# In control_test.exs, add to classify/1 describe block:
test "classifies control_cancel_request messages" do
  msg = %{"type" => "control_cancel_request", "request_id" => "req_1"}
  assert {:control_cancel, ^msg} = Control.classify(msg)
end
```

**Step 2: Run test, verify fail**

**Step 3: Add classify clause**

In `lib/claude_code/cli/control.ex`, add before the catch-all `classify/1`:

```elixir
def classify(%{"type" => "control_cancel_request"} = msg), do: {:control_cancel, msg}
```

Update the typespec:

```elixir
@spec classify(map()) :: {:control_request, map()} | {:control_response, map()} | {:control_cancel, map()} | {:message, map()}
```

**Step 4: Run test, verify pass**

**Step 5:** Handle in `Adapter.Port`. In `process_message/2` (~line 528), add a case:

```elixir
{:control_cancel, msg} ->
  handle_control_cancel(msg, state)
```

Add the handler:

```elixir
defp handle_control_cancel(%{"request_id" => cancel_id}, state) do
  Logger.debug("Received control cancel for request: #{cancel_id}")
  # Remove the pending request so we don't wait for a response that won't come
  case Map.pop(state.pending_control_requests, cancel_id) do
    {nil, _} -> state
    {from, remaining} ->
      case from do
        {:initialize, session} ->
          Adapter.notify_status(session, {:error, :cancelled})
        _ ->
          GenServer.reply(from, {:error, :cancelled})
      end
      %{state | pending_control_requests: remaining}
  end
end
```

**Step 6: Commit**

```
git commit -am "feat: handle inbound control_cancel_request messages"
```

---

## Phase 4: Initialize Response Parsing

### Task 12: Wire `ModelInfo`/`AgentInfo`/`AccountInfo` into initialize response

Currently `handle_control_response/2` stores the raw response map in `state.server_info` when the initialize succeeds. Parse the known fields into structs.

**Files:**
- Modify: `lib/claude_code/adapter/port.ex` (~line 563)
- Modify: `test/claude_code/adapter/port_test.exs` (if there are init tests)

**Step 1:** Create a helper function in `Adapter.Port`:

```elixir
defp parse_initialize_response(response) when is_map(response) do
  response
  |> maybe_parse_list("models", &ClaudeCode.Model.Info.new/1)
  |> maybe_parse_list("agents", &ClaudeCode.AgentInfo.new/1)
  |> maybe_parse_map("account", &ClaudeCode.AccountInfo.new/1)
end

defp maybe_parse_list(response, key, parser) do
  case Map.get(response, key) do
    list when is_list(list) -> Map.put(response, key, Enum.map(list, parser))
    _ -> response
  end
end

defp maybe_parse_map(response, key, parser) do
  case Map.get(response, key) do
    map when is_map(map) -> Map.put(response, key, parser.(map))
    _ -> response
  end
end
```

**Step 2:** Call it in `handle_control_response/2` where the initialize response is stored:

Change (~line 564):
```elixir
# Before:
%{state | pending_control_requests: remaining, server_info: response, status: :ready}

# After:
%{state | pending_control_requests: remaining, server_info: parse_initialize_response(response), status: :ready}
```

**Step 3:** Run tests, verify pass.

**Step 4: Commit**

```
git commit -am "feat: parse initialize response into ModelInfo/AgentInfo/AccountInfo structs"
```

---

### Task 13: Add convenience accessors to public API

**Files:**
- Modify: `lib/claude_code.ex`

**Step 1:** Add typed accessors that pull from `get_server_info`:

```elixir
@doc """
Returns the list of available models from the initialization response.

## Examples

    {:ok, models} = ClaudeCode.supported_models(session)
    Enum.each(models, &IO.puts(&1.display_name))
"""
@spec supported_models(session()) :: {:ok, [ClaudeCode.Model.Info.t()]} | {:error, term()}
def supported_models(session) do
  case get_server_info(session) do
    {:ok, %{"models" => models}} when is_list(models) -> {:ok, models}
    {:ok, _} -> {:ok, []}
    error -> error
  end
end

@doc """
Returns the list of available subagents from the initialization response.

## Examples

    {:ok, agents} = ClaudeCode.supported_agents(session)
"""
@spec supported_agents(session()) :: {:ok, [ClaudeCode.AgentInfo.t()]} | {:error, term()}
def supported_agents(session) do
  case get_server_info(session) do
    {:ok, %{"agents" => agents}} when is_list(agents) -> {:ok, agents}
    {:ok, _} -> {:ok, []}
    error -> error
  end
end

@doc """
Returns account information from the initialization response.

## Examples

    {:ok, account} = ClaudeCode.account_info(session)
    IO.puts(account.email)
"""
@spec account_info(session()) :: {:ok, ClaudeCode.AccountInfo.t() | nil} | {:error, term()}
def account_info(session) do
  case get_server_info(session) do
    {:ok, %{"account" => account}} -> {:ok, account}
    {:ok, _} -> {:ok, nil}
    error -> error
  end
end
```

**Step 2:** Run `mix quality`.

**Step 3: Commit**

```
git commit -am "feat: add supported_models, supported_agents, account_info accessors"
```

---

## Phase 5: Update type-mapping and quality check

### Task 14: Update type-mapping.md

**Files:**
- Modify: `.claude/skills/cli-sync/references/type-mapping.md`

**Step 1:** Update the control protocol coverage table — change all "Not implemented" entries to "Implemented" for the new builders.

**Step 2:** Update the inbound section for `elicitation` (logged, not fully implemented) and `control_cancel_request` (implemented).

**Step 3:** Update the response parsing section for `SDKControlInitializeResponse` — now parses into typed structs.

**Step 4: Commit**

```
git commit -am "docs: update type-mapping with control protocol coverage"
```

---

### Task 15: Final quality check

**Step 1:** Run `mix quality`

Expected: All checks pass (compile, format, credo, dialyzer)

**Step 2:** Run `mix test`

Expected: All tests pass

**Step 3:** If anything fails, fix and re-run.

**Step 4: Final commit if fixes were needed**
