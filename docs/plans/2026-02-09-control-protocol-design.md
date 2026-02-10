# Control Protocol Design

> **Status:** Proposed

**Goal:** Implement the bidirectional control protocol between the Elixir SDK and the Claude CLI, enabling initialize handshakes, interrupt, dynamic model/permission changes, MCP status queries, and file rewind. This is the foundation for future hooks, tool permissions, and in-process MCP servers.

**Scope:** Outbound control requests only (SDK → CLI → response). Inbound control requests (CLI → SDK, e.g., `can_use_tool`, `hook_callback`) are stubbed but not dispatched to user callbacks.

**Tech Stack:** Elixir, GenServer, Jason, NimbleOptions

---

## Architecture

The control protocol shares the same stdin/stdout transport as regular messages. Control messages are distinguished by their `"type"` field and routed separately from SDK messages. They never reach the user's message stream.

### Wire Format

All messages are newline-delimited JSON on stdin/stdout.

**Outbound control request (SDK → CLI):**

```json
{
  "type": "control_request",
  "request_id": "req_1_a1b2c3d4",
  "request": {
    "subtype": "initialize",
    ...
  }
}
```

**Inbound control response (CLI → SDK):**

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "req_1_a1b2c3d4",
    "response": { ... }
  }
}
```

**Error response (either direction):**

```json
{
  "type": "control_response",
  "response": {
    "subtype": "error",
    "request_id": "req_1_a1b2c3d4",
    "error": "Error message"
  }
}
```

**Inbound control request (CLI → SDK, stubbed for now):**

```json
{
  "type": "control_request",
  "request_id": "<cli-generated-id>",
  "request": {
    "subtype": "can_use_tool",
    "tool_name": "Bash",
    "input": { ... }
  }
}
```

### Message Type Routing

The `"type"` field on each JSON object determines routing:

| `type` value | Direction | Routing |
|---|---|---|
| `"control_response"` | CLI → SDK | Match by `request_id`, resolve pending outbound request (stays in adapter) |
| `"control_request"` | CLI → SDK | Stub: log warning, send error response (future: forward to Session) |
| All other types | CLI → SDK | Existing path: `Parser.parse_message` → `notify_message` to Session |
| `"control_request"` | SDK → CLI | Built by `CLI.Control`, written to stdin by adapter |
| `"control_response"` | SDK → CLI | Built by `CLI.Control`, written to stdin by adapter (future: answering CLI requests) |

### Three-Layer Placement

```
CLI protocol layer (shared)     →  CLI.Control (new), CLI.Command, CLI.Input, CLI.Parser
Adapter layer (per-environment) →  Adapter.Local (modified), Adapter.Test (unchanged)
Core layer (adapter-agnostic)   →  Session (modified), ClaudeCode (modified), Stream, Options, Types
```

`CLI.Control` is pure functions (no state, no processes) in the CLI protocol layer. It knows the wire format but nothing about Ports or GenServers. When a remote adapter arrives, it imports the same module.

---

## New Module: `CLI.Control`

**File:** `lib/claude_code/cli/control.ex`

Responsibilities:
- Classify incoming JSON as `:control_request`, `:control_response`, or `:message`
- Generate unique request IDs (monotonic counter + random hex)
- Build outgoing control request JSON
- Build outgoing control response JSON

### Public API

```elixir
defmodule ClaudeCode.CLI.Control do
  @moduledoc """
  Bidirectional control protocol for the Claude CLI.

  Builds and classifies control messages that share the stdin/stdout
  transport with regular SDK messages. Part of the CLI protocol layer.
  """

  # --- Classification ---

  @spec classify(map()) :: {:control_request, map()} | {:control_response, map()} | {:message, map()}
  def classify(%{"type" => "control_request"} = msg), do: {:control_request, msg}
  def classify(%{"type" => "control_response"} = msg), do: {:control_response, msg}
  def classify(msg), do: {:message, msg}

  # --- Request ID Generation ---

  @spec generate_request_id(non_neg_integer()) :: String.t()
  def generate_request_id(counter)
  # Returns "req_{counter}_{random_hex}"

  # --- Outbound Request Builders (SDK → CLI) ---

  @spec initialize_request(String.t(), map() | nil, map() | nil) :: String.t()
  def initialize_request(request_id, hooks \\ nil, agents \\ nil)

  @spec interrupt_request(String.t()) :: String.t()
  def interrupt_request(request_id)

  @spec set_model_request(String.t(), String.t()) :: String.t()
  def set_model_request(request_id, model)

  @spec set_permission_mode_request(String.t(), String.t()) :: String.t()
  def set_permission_mode_request(request_id, mode)

  @spec rewind_files_request(String.t(), String.t()) :: String.t()
  def rewind_files_request(request_id, user_message_id)

  @spec mcp_status_request(String.t()) :: String.t()
  def mcp_status_request(request_id)

  # --- Response Builders (SDK → CLI, answering CLI requests) ---

  @spec success_response(String.t(), map()) :: String.t()
  def success_response(request_id, response_data)

  @spec error_response(String.t(), String.t()) :: String.t()
  def error_response(request_id, error_message)

  # --- Response Parsing (CLI → SDK) ---

  @spec parse_control_response(map()) :: {:ok, String.t(), map()} | {:error, String.t(), String.t()}
  def parse_control_response(msg)
  # Returns {:ok, request_id, response_data} or {:error, request_id, error_message}
end
```

Each builder returns a JSON string with a trailing newline, ready to write to stdin.

---

## Adapter Changes

### Adapter Behaviour

**New optional callbacks:**

```elixir
@callback send_control_request(adapter :: pid(), subtype :: atom(), params :: map()) ::
            {:ok, map()} | {:error, term()}

@callback send_control_response(adapter :: pid(), request_id :: String.t(), response :: map()) ::
            :ok | {:error, term()}

@callback get_server_info(adapter :: pid()) :: {:ok, map()} | {:error, term()}
```

**New notification helper:**

```elixir
@spec notify_control_request(pid(), String.t(), map()) :: :ok
def notify_control_request(session, request_id, request) do
  send(session, {:adapter_control_request, request_id, request})
  :ok
end
```

### Adapter.Local Changes

**New state fields:**

```elixir
defstruct [
  # ... existing fields ...
  :server_info,              # cached initialize response (map)
  control_counter: 0,        # monotonic counter for request IDs
  pending_control_requests: %{}  # %{request_id => GenServer from}
]
```

**Lifecycle change - initialize handshake:**

Current flow:
```
Port opened → notify_status(:ready)
```

New flow:
```
Port opened → send initialize request → await response → cache server_info → notify_status(:ready)
```

The initialize request is sent in `handle_info({:cli_resolved, {:ok, ...}})` after `open_cli_port` succeeds. The adapter does NOT notify `:ready` until the initialize response arrives. If the response times out (60s default, configurable via `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT` env var), the adapter notifies `{:error, :initialize_timeout}`.

Queries queued in Session during provisioning stay queued through the handshake. The existing queue mechanism handles this naturally.

**Message routing change in `process_line`:**

```elixir
defp process_line(line, state) do
  case Jason.decode(line) do
    {:ok, json} ->
      case CLI.Control.classify(json) do
        {:control_response, msg} ->
          handle_control_response(msg, state)

        {:control_request, msg} ->
          handle_inbound_control_request(msg, state)

        {:message, json} ->
          handle_sdk_message(json, state)
      end

    {:error, _} ->
      Logger.debug("Failed to decode JSON: #{line}")
      state
  end
end
```

`handle_sdk_message/2` contains the existing `Parser.parse_message` → `notify_message` logic.

**Outbound control request tracking:**

```elixir
def handle_call({:control_request, subtype, params}, from, state) do
  {request_id, new_counter} = next_request_id(state.control_counter)
  json = build_control_request(subtype, request_id, params)

  Port.command(state.port, json <> "\n")

  pending = Map.put(state.pending_control_requests, request_id, from)
  schedule_control_timeout(request_id, @control_timeout)

  {:noreply, %{state | control_counter: new_counter, pending_control_requests: pending}}
end
```

When the matching `control_response` arrives on stdout:

```elixir
defp handle_control_response(msg, state) do
  case CLI.Control.parse_control_response(msg) do
    {:ok, request_id, response} ->
      case Map.pop(state.pending_control_requests, request_id) do
        {nil, _} ->
          Logger.warning("Received control response for unknown request: #{request_id}")
          state

        {from, remaining} ->
          GenServer.reply(from, {:ok, response})
          %{state | pending_control_requests: remaining}
      end

    {:error, request_id, error_msg} ->
      case Map.pop(state.pending_control_requests, request_id) do
        {nil, _} -> state
        {from, remaining} ->
          GenServer.reply(from, {:error, error_msg})
          %{state | pending_control_requests: remaining}
      end
  end
end
```

**Inbound control request stub:**

```elixir
defp handle_inbound_control_request(msg, state) do
  request_id = get_in(msg, ["request_id"])
  subtype = get_in(msg, ["request", "subtype"])
  Logger.warning("Received unhandled control request: #{subtype}")

  response = CLI.Control.error_response(request_id, "Not implemented: #{subtype}")
  Port.command(state.port, response <> "\n")
  state
end
```

This stub becomes the dispatch point for hooks and permissions later.

**Control timeout handling:**

```elixir
def handle_info({:control_timeout, request_id}, state) do
  case Map.pop(state.pending_control_requests, request_id) do
    {nil, _} -> {:noreply, state}
    {from, remaining} ->
      GenServer.reply(from, {:error, :control_timeout})
      {:noreply, %{state | pending_control_requests: remaining}}
  end
end
```

**Port disconnect cleanup:**

When the port disconnects, fail all pending control requests immediately:

```elixir
defp handle_port_disconnect(state, error) do
  # Fail pending control requests
  for {_req_id, from} <- state.pending_control_requests do
    GenServer.reply(from, {:error, error})
  end

  # Existing: fail current SDK request
  if state.current_request do
    Adapter.notify_error(state.session, state.current_request, error)
  end

  %{state | port: nil, current_request: nil, buffer: "",
    status: :disconnected, pending_control_requests: %{}}
end
```

**Write serialization:** Not needed. The Adapter.Local GenServer processes one message at a time, so `Port.command` calls never interleave. This is simpler than Python's `anyio.Lock` approach.

---

## Session Changes

**New `handle_call` clause:**

```elixir
def handle_call({:control, subtype, params}, _from, state) do
  if supports_control?(state.adapter_module) do
    case state.adapter_module.send_control_request(state.adapter_pid, subtype, params) do
      {:ok, response} -> {:reply, {:ok, response}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  else
    {:reply, {:error, :not_supported}, state}
  end
end

def handle_call(:get_server_info, _from, state) do
  if supports_control?(state.adapter_module) do
    {:reply, state.adapter_module.get_server_info(state.adapter_pid), state}
  else
    {:reply, {:error, :not_supported}, state}
  end
end
```

**Guard function:**

```elixir
defp supports_control?(adapter_module) do
  function_exported?(adapter_module, :send_control_request, 3)
end
```

**Stub for future inbound control requests:**

```elixir
def handle_info({:adapter_control_request, request_id, request}, state) do
  # Future: dispatch to can_use_tool/hooks callbacks
  Logger.warning("Received unhandled control request from adapter: #{inspect(request)}")
  {:noreply, state}
end
```

---

## Public API Changes

**New functions in `ClaudeCode`:**

```elixir
@doc "Interrupt the current generation."
@spec interrupt(session()) :: {:ok, map()} | {:error, term()}
def interrupt(session) do
  GenServer.call(session, {:control, :interrupt, %{}})
end

@doc "Change the model mid-conversation."
@spec set_model(session(), String.t()) :: {:ok, map()} | {:error, term()}
def set_model(session, model) do
  GenServer.call(session, {:control, :set_model, %{model: model}})
end

@doc "Change the permission mode mid-conversation."
@spec set_permission_mode(session(), atom()) :: {:ok, map()} | {:error, term()}
def set_permission_mode(session, mode) do
  GenServer.call(session, {:control, :set_permission_mode, %{mode: mode}})
end

@doc "Query MCP server connection status."
@spec get_mcp_status(session()) :: {:ok, map()} | {:error, term()}
def get_mcp_status(session) do
  GenServer.call(session, {:control, :mcp_status, %{}})
end

@doc "Get server initialization info (commands, output styles, capabilities)."
@spec get_server_info(session()) :: {:ok, map()} | {:error, term()}
def get_server_info(session) do
  GenServer.call(session, :get_server_info)
end

@doc "Rewind tracked files to the state at a specific user message checkpoint."
@spec rewind_files(session(), String.t()) :: {:ok, map()} | {:error, term()}
def rewind_files(session, user_message_id) do
  GenServer.call(session, {:control, :rewind_files, %{user_message_id: user_message_id}})
end
```

---

## Options Changes

**`:agents` moves from CLI flag to control protocol:**

In `CLI.Command`, add `:agents` to the list of Elixir-only options that don't become CLI flags:

```elixir
defp convert_option(:agents, _value), do: nil
```

Instead, agents are passed through the initialize handshake. The adapter reads `:agents` from session options and includes them in the initialize request.

---

## What This Enables (Future Work)

With the control protocol plumbing in place, these features become incremental additions:

1. **Tool permission callbacks** (`can_use_tool`) - Fill in the inbound stub in Adapter.Local to forward `can_use_tool` requests to Session. Add `:can_use_tool` option. Session invokes the callback in a Task and sends the response back.

2. **Hook system** - Same pattern. The initialize handshake already has a `hooks` field. Register hook callback IDs during initialize. When `hook_callback` requests arrive, dispatch to the registered functions.

3. **In-process MCP servers** - Route `mcp_message` requests to Elixir MCP server processes. The initialize handshake would declare SDK server capabilities.

Each builds on the routing, request tracking, and response infrastructure established here.

---

## Testing Strategy

1. **`CLI.Control` unit tests** - Pure function tests: classify, build requests/responses, generate IDs, parse responses.

2. **`Adapter.Local` control routing tests** - Feed control JSON through `process_line` and verify routing (control_response resolves pending, control_request sends error stub, regular messages pass through).

3. **`Adapter.Local` initialize handshake tests** - Verify lifecycle: port opens → initialize sent → response received → status becomes `:ready`. Verify timeout: no response → status becomes `{:error, :initialize_timeout}`.

4. **`Adapter.Local` outbound request tests** - Send control request, simulate control_response on stdout, verify caller gets the response. Test timeout. Test port disconnect fails pending requests.

5. **Integration tests** - Full Session → Adapter → mock CLI flow for `interrupt`, `set_model`, etc. Use `Adapter.Test` or a mock Port.

6. **`ClaudeCode` public API tests** - Verify new functions reach the adapter correctly. Test `:not_supported` when adapter doesn't implement control.
