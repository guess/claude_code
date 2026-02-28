# Remote Adapter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the parsing layer so adapters are pure transport, then add a WebSocket-based remote adapter and an Adapter.Local-based sidecar, enabling CC sessions to run on a remote server.

**Architecture:** Move message parsing from `Adapter.Local` to `Session`. Add `ClaudeCode.Remote.Protocol` for the WebSocket envelope format. Add `ClaudeCode.Adapter.Remote` as a WebSocket client. Add `claude_code_sidecar` package in `sidecar/` that uses `Adapter.Local` internally and bridges CLI messages over WebSocket.

**Tech Stack:** `mint_web_socket` (adapter WS client), `bandit` + `websock` (sidecar WS server), `Jason` (JSON encoding, matching existing codebase), existing `ClaudeCode.Adapter` behaviour.

**Design doc:** `docs/plans/2026-02-27-cc-remote-adapter.md`

---

## Phase 0: Refactor Parsing Layer

Move CC message parsing from `Adapter.Local` to `Session`. Adapters become pure transport — they forward raw JSON, Session parses once.

### Task 1: Add `notify_raw_message` to Adapter + Session

**Files:**
- Modify: `lib/claude_code/adapter.ex`
- Modify: `lib/claude_code/session.ex`
- Modify: `test/claude_code/session_test.exs`

**Step 1: Write the failing test**

Add a test to `session_test.exs` that sends a raw JSON map directly to Session via the new message tuple and verifies it gets parsed and delivered:

```elixir
describe "raw message handling" do
  test "parses and delivers raw JSON map from adapter" do
    # Use the Test adapter for setup, but simulate raw message delivery
    ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
      [ClaudeCode.Test.result("stub result")]
    end)

    {:ok, session} = Session.start_link(adapter: @adapter)

    # Simulate what a raw-forwarding adapter would send
    raw_result = %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "duration_ms" => 100.0,
      "duration_api_ms" => 80.0,
      "num_turns" => 1,
      "result" => "Hello from raw!",
      "session_id" => "test-session",
      "total_cost_usd" => 0.001,
      "usage" => %{
        "input_tokens" => 10,
        "output_tokens" => 5,
        "cache_creation_input_tokens" => 0,
        "cache_read_input_tokens" => 0,
        "server_tool_use_input_tokens" => 0
      }
    }

    # Start a query to create a request
    {:ok, request_id} = GenServer.call(session, {:query_stream, "test", []})

    # Send raw message directly (simulating adapter)
    send(session, {:adapter_raw_message, request_id, raw_result})

    # Should receive parsed ResultMessage
    {:message, message} = GenServer.call(session, {:receive_next, request_id})
    assert %ClaudeCode.Message.ResultMessage{} = message
    assert message.result == "Hello from raw!"

    # ResultMessage should auto-trigger done
    assert :done = GenServer.call(session, {:receive_next, request_id})
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/session_test.exs --seed 0`
Expected: FAIL — `{:adapter_raw_message, ...}` not handled

**Step 3: Add `notify_raw_message` to Adapter module**

Add to `lib/claude_code/adapter.ex`:

```elixir
@doc """
Sends a raw JSON message to the session for parsing and delivery.

Adapters that forward unparsed CLI output use this instead of
`notify_message/3`. Session handles JSON decoding (if binary)
and struct parsing via `CLI.Parser`.
"""
@spec notify_raw_message(pid(), reference(), map() | binary()) :: :ok
def notify_raw_message(session, request_id, raw) do
  send(session, {:adapter_raw_message, request_id, raw})
  :ok
end
```

**Step 4: Add raw message handler to Session**

Add to `lib/claude_code/session.ex`, in the `handle_info` clauses:

```elixir
def handle_info({:adapter_raw_message, request_id, raw}, state) do
  with {:ok, json_map} <- decode_if_binary(raw),
       {:ok, message} <- ClaudeCode.CLI.Parser.parse_message(json_map) do
    # Extract session ID (same as existing adapter_message path)
    new_session_id = extract_session_id(message) || state.session_id
    state = %{state | session_id: new_session_id}

    case Map.get(state.requests, request_id) do
      nil ->
        {:noreply, state}

      request ->
        updated_request = dispatch_message(message, request)
        new_requests = Map.put(state.requests, request_id, updated_request)
        state = %{state | requests: new_requests}

        # Auto-detect ResultMessage → mark request done
        if match?(%ClaudeCode.Message.ResultMessage{}, message) do
          handle_info({:adapter_done, request_id, :completed}, state)
        else
          {:noreply, state}
        end
    end
  else
    {:error, reason} ->
      require Logger
      Logger.warning("Failed to parse raw message: #{inspect(reason)}")
      {:noreply, state}
  end
end

defp decode_if_binary(raw) when is_binary(raw), do: Jason.decode(raw)
defp decode_if_binary(raw) when is_map(raw), do: {:ok, raw}
```

**Step 5: Run test to verify it passes**

Run: `mix test test/claude_code/session_test.exs --seed 0`
Expected: All pass (existing tests + new test)

**Step 6: Commit**

```
git add lib/claude_code/adapter.ex lib/claude_code/session.ex test/claude_code/session_test.exs
git commit -m "feat: add notify_raw_message — Session parses raw JSON from adapters"
```

---

### Task 2: Migrate Adapter.Local to Use `notify_raw_message`

**Files:**
- Modify: `lib/claude_code/adapter/local.ex`

**Step 1: Run existing tests to establish baseline**

Run: `mix test`
Expected: All pass

**Step 2: Modify `handle_sdk_message/2`**

Replace the current implementation that parses and notifies with raw forwarding. Find the `handle_sdk_message/2` function in `local.ex` and change it:

Before (current):
```elixir
defp handle_sdk_message(_json, %{current_request: nil} = state), do: state

defp handle_sdk_message(json, state) do
  case Parser.parse_message(json) do
    {:ok, message} ->
      Adapter.notify_message(state.session, state.current_request, message)

      if match?(%ResultMessage{}, message) do
        Adapter.notify_done(state.session, state.current_request, :completed)
        %{state | current_request: nil}
      else
        state
      end

    {:error, _} ->
      Logger.debug("Failed to parse message: #{inspect(json)}")
      state
  end
end
```

After (refactored):
```elixir
defp handle_sdk_message(_json, %{current_request: nil} = state), do: state

defp handle_sdk_message(json, state) do
  Adapter.notify_raw_message(state.session, state.current_request, json)

  if json["type"] == "result" do
    %{state | current_request: nil}
  else
    state
  end
end
```

Note: `json` is already a decoded map (from `process_line/2` which calls `Jason.decode`). We peek at `"type"` to reset `current_request` — no struct parsing needed.

Also remove the `alias ClaudeCode.Message.ResultMessage` if it's only used here, and remove the `Parser` alias if no longer needed in the adapter. Check for other uses first.

**Step 3: Run all tests**

Run: `mix test`
Expected: All pass — Session now handles parsing for both raw and parsed paths.

**Step 4: Run quality checks**

Run: `mix quality`
Expected: All pass. Fix any unused alias warnings.

**Step 5: Commit**

```
git add lib/claude_code/adapter/local.ex
git commit -m "refactor: move CC message parsing from Adapter.Local to Session"
```

---

## Phase 1: Shared Protocol

### Task 3: Protocol — Envelope Message Encoding

**Files:**
- Create: `lib/claude_code/remote/protocol.ex`
- Create: `test/claude_code/remote/protocol_test.exs`

The Protocol module handles only the **envelope** messages (init, query, ready, done, error, stop, interrupt). CC messages are forwarded as raw NDJSON — the Protocol never touches them.

**Step 1: Write the failing tests**

```elixir
# test/claude_code/remote/protocol_test.exs
defmodule ClaudeCode.Remote.ProtocolTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Remote.Protocol

  # Host → Sidecar encoding

  describe "encode_init/1" do
    test "encodes init message with protocol version" do
      opts = %{
        session_opts: %{model: "sonnet", system_prompt: "You are helpful."},
        workspace_id: "agent_abc123"
      }

      {:ok, json} = Protocol.encode_init(opts)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "init"
      assert decoded["protocol_version"] == 1
      assert decoded["workspace_id"] == "agent_abc123"
      assert decoded["session_opts"]["model"] == "sonnet"
      refute Map.has_key?(decoded, "resume")
    end

    test "includes resume when provided" do
      opts = %{session_opts: %{}, workspace_id: "ws1", resume: "session-uuid"}

      {:ok, json} = Protocol.encode_init(opts)
      assert Jason.decode!(json)["resume"] == "session-uuid"
    end
  end

  describe "encode_query/1" do
    test "encodes query message" do
      msg = %{request_id: "req-1", prompt: "Hello", opts: %{max_turns: 5}}

      {:ok, json} = Protocol.encode_query(msg)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "query"
      assert decoded["request_id"] == "req-1"
      assert decoded["prompt"] == "Hello"
    end
  end

  describe "encode_stop/0" do
    test "encodes stop message" do
      {:ok, json} = Protocol.encode_stop()
      assert Jason.decode!(json)["type"] == "stop"
    end
  end

  describe "encode_interrupt/0" do
    test "encodes interrupt message" do
      {:ok, json} = Protocol.encode_interrupt()
      assert Jason.decode!(json)["type"] == "interrupt"
    end
  end

  # Sidecar → Host encoding

  describe "encode_ready/1" do
    test "encodes ready ack" do
      {:ok, json} = Protocol.encode_ready("session-456")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "ready"
      assert decoded["session_id"] == "session-456"
    end
  end

  describe "encode_message/2" do
    test "wraps raw NDJSON line in envelope" do
      raw_line = ~s({"type":"assistant","message":{"role":"assistant"}})
      {:ok, json} = Protocol.encode_message("req-1", raw_line)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "message"
      assert decoded["request_id"] == "req-1"
      # payload is the raw string, not parsed
      assert decoded["payload"] == raw_line
    end
  end

  describe "encode_done/2" do
    test "encodes done" do
      {:ok, json} = Protocol.encode_done("req-1", "completed")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "done"
      assert decoded["request_id"] == "req-1"
      assert decoded["reason"] == "completed"
    end
  end

  describe "encode_error/3" do
    test "encodes error" do
      {:ok, json} = Protocol.encode_error("req-1", "session_failed", "CLI exited")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "error"
      assert decoded["code"] == "session_failed"
    end
  end

  # Decoding (both directions)

  describe "decode/1" do
    test "decodes all envelope types" do
      assert {:ok, %{type: :init}} = Protocol.decode(~s({"type":"init","protocol_version":1,"workspace_id":"w","session_opts":{}}))
      assert {:ok, %{type: :ready}} = Protocol.decode(~s({"type":"ready","session_id":"s"}))
      assert {:ok, %{type: :query}} = Protocol.decode(~s({"type":"query","request_id":"r","prompt":"p","opts":{}}))
      assert {:ok, %{type: :message}} = Protocol.decode(~s({"type":"message","request_id":"r","payload":"raw"}))
      assert {:ok, %{type: :done}} = Protocol.decode(~s({"type":"done","request_id":"r","reason":"completed"}))
      assert {:ok, %{type: :error}} = Protocol.decode(~s({"type":"error","request_id":"r","code":"c","details":"d"}))
      assert {:ok, %{type: :stop}} = Protocol.decode(~s({"type":"stop"}))
      assert {:ok, %{type: :interrupt}} = Protocol.decode(~s({"type":"interrupt"}))
    end

    test "message payload preserved as raw string" do
      raw = ~s({"type":"assistant","content":[]})
      json = Jason.encode!(%{type: "message", request_id: "r", payload: raw})
      {:ok, decoded} = Protocol.decode(json)
      assert decoded.payload == raw
    end

    test "returns error for unknown type" do
      assert {:error, {:unknown_message_type, "bogus"}} = Protocol.decode(~s({"type":"bogus"}))
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Protocol.decode("not json")
    end

    test "validates protocol version on init" do
      assert {:error, {:unsupported_protocol_version, 99}} =
               Protocol.decode(~s({"type":"init","protocol_version":99,"workspace_id":"w","session_opts":{}}))
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/remote/protocol_test.exs`
Expected: Compilation error — module not found

**Step 3: Write implementation**

```elixir
# lib/claude_code/remote/protocol.ex
defmodule ClaudeCode.Remote.Protocol do
  @moduledoc """
  Shared envelope encoding/decoding for the ClaudeCode remote WebSocket protocol.

  This module handles **only** the protocol envelope messages (init, query, ready,
  done, error, stop, interrupt). CC messages (assistant, result, system, etc.) are
  forwarded as raw NDJSON strings — the Protocol never parses them.

  ## Protocol Version

  The `init` message includes `protocol_version: 1`. The sidecar validates
  this before accepting the connection.
  """

  @protocol_version 1

  @doc "Returns the current protocol version."
  @spec protocol_version() :: pos_integer()
  def protocol_version, do: @protocol_version

  # ============================================================================
  # Host → Sidecar
  # ============================================================================

  @spec encode_init(map()) :: {:ok, String.t()}
  def encode_init(%{session_opts: session_opts, workspace_id: workspace_id} = opts) do
    message =
      %{type: "init", protocol_version: @protocol_version, workspace_id: workspace_id, session_opts: session_opts}
      |> maybe_put(:resume, Map.get(opts, :resume))

    {:ok, Jason.encode!(message)}
  end

  @spec encode_query(map()) :: {:ok, String.t()}
  def encode_query(%{request_id: request_id, prompt: prompt} = msg) do
    {:ok, Jason.encode!(%{type: "query", request_id: request_id, prompt: prompt, opts: Map.get(msg, :opts, %{})})}
  end

  @spec encode_stop() :: {:ok, String.t()}
  def encode_stop, do: {:ok, Jason.encode!(%{type: "stop"})}

  @spec encode_interrupt() :: {:ok, String.t()}
  def encode_interrupt, do: {:ok, Jason.encode!(%{type: "interrupt"})}

  # ============================================================================
  # Sidecar → Host
  # ============================================================================

  @spec encode_ready(String.t()) :: {:ok, String.t()}
  def encode_ready(session_id) do
    {:ok, Jason.encode!(%{type: "ready", session_id: session_id})}
  end

  @doc "Wraps a raw NDJSON line in a message envelope. Payload is NOT parsed."
  @spec encode_message(String.t(), String.t()) :: {:ok, String.t()}
  def encode_message(request_id, raw_ndjson_line) do
    {:ok, Jason.encode!(%{type: "message", request_id: request_id, payload: raw_ndjson_line})}
  end

  @spec encode_done(String.t(), String.t()) :: {:ok, String.t()}
  def encode_done(request_id, reason) do
    {:ok, Jason.encode!(%{type: "done", request_id: request_id, reason: reason})}
  end

  @spec encode_error(String.t(), String.t(), String.t()) :: {:ok, String.t()}
  def encode_error(request_id, code, details) do
    {:ok, Jason.encode!(%{type: "error", request_id: request_id, code: code, details: details})}
  end

  # ============================================================================
  # Decoding (both directions)
  # ============================================================================

  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(json) do
    case Jason.decode(json) do
      {:ok, %{"type" => type} = raw} -> decode_typed(type, raw)
      {:ok, _} -> {:error, :missing_type_field}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp decode_typed("init", %{"protocol_version" => v} = raw) when v == @protocol_version do
    {:ok, %{type: :init, protocol_version: v, workspace_id: raw["workspace_id"], session_opts: raw["session_opts"], resume: raw["resume"]}}
  end

  defp decode_typed("init", %{"protocol_version" => v}), do: {:error, {:unsupported_protocol_version, v}}

  defp decode_typed("ready", raw), do: {:ok, %{type: :ready, session_id: raw["session_id"]}}
  defp decode_typed("query", raw), do: {:ok, %{type: :query, request_id: raw["request_id"], prompt: raw["prompt"], opts: raw["opts"]}}
  defp decode_typed("message", raw), do: {:ok, %{type: :message, request_id: raw["request_id"], payload: raw["payload"]}}
  defp decode_typed("done", raw), do: {:ok, %{type: :done, request_id: raw["request_id"], reason: raw["reason"]}}
  defp decode_typed("error", raw), do: {:ok, %{type: :error, request_id: raw["request_id"], code: raw["code"], details: raw["details"]}}
  defp decode_typed("control", raw), do: {:ok, %{type: :control, request_id: raw["request_id"], subtype: raw["subtype"], params: raw["params"]}}
  defp decode_typed("control_response", raw), do: {:ok, %{type: :control_response, request_id: raw["request_id"], response: raw["response"]}}
  defp decode_typed("stop", _), do: {:ok, %{type: :stop}}
  defp decode_typed("interrupt", _), do: {:ok, %{type: :interrupt}}
  defp decode_typed(unknown, _), do: {:error, {:unknown_message_type, unknown}}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
```

**Step 4: Run tests**

Run: `mix test test/claude_code/remote/protocol_test.exs`
Expected: All pass

**Step 5: Commit**

```
git add lib/claude_code/remote/protocol.ex test/claude_code/remote/protocol_test.exs
git commit -m "feat: add Remote.Protocol with envelope encoding/decoding"
```

---

## Phase 2: Remote Adapter

### Task 4: Add `mint_web_socket` Dependency

**Files:**
- Modify: `mix.exs`

**Step 1: Add dependency**

Add to `deps()` in production section:

```elixir
{:mint_web_socket, "~> 1.0"},
```

Also move `bandit` from `only: :dev` to `only: [:dev, :test]` (needed for mock sidecar in tests):

```elixir
{:bandit, "~> 1.0", only: [:dev, :test]},
```

Add `websock_adapter` for test mock:

```elixir
{:websock_adapter, "~> 0.5", only: [:dev, :test]},
```

**Step 2: Fetch and compile**

Run: `mix deps.get && mix compile`
Expected: Clean

**Step 3: Commit**

```
git add mix.exs mix.lock
git commit -m "deps: add mint_web_socket, bandit/websock_adapter for test"
```

---

### Task 5: Remote Adapter — GenServer with Config Validation

**Files:**
- Create: `lib/claude_code/adapter/remote.ex`
- Create: `test/claude_code/adapter/remote_test.exs`

**Step 1: Write failing tests**

```elixir
# test/claude_code/adapter/remote_test.exs
defmodule ClaudeCode.Adapter.RemoteTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Remote

  describe "config validation" do
    test "requires url" do
      assert {:error, _} = Remote.validate_config(auth_token: "tok")
    end

    test "requires auth_token" do
      assert {:error, _} = Remote.validate_config(url: "wss://example.com/sessions")
    end

    test "accepts valid config with defaults" do
      assert {:ok, config} = Remote.validate_config(url: "wss://x.com/s", auth_token: "t")
      assert config[:connect_timeout] == 10_000
      assert config[:init_timeout] == 30_000
      assert is_binary(config[:workspace_id])
    end
  end

  describe "parse_url/1" do
    test "parses wss" do
      assert {:ok, :https, "example.com", 443, "/sessions"} = Remote.parse_url("wss://example.com/sessions")
    end

    test "parses ws with port" do
      assert {:ok, :http, "localhost", 4040, "/s"} = Remote.parse_url("ws://localhost:4040/s")
    end

    test "rejects invalid scheme" do
      assert {:error, _} = Remote.parse_url("http://example.com")
    end
  end
end
```

**Step 2: Run to verify failure, then implement**

The adapter GenServer skeleton: config validation, URL parsing, struct, start_link/init, health, stop. WebSocket connection in `handle_continue(:connect)`. Query sending via `handle_call({:query, ...})`. Message forwarding: receive WebSocket text frames → `notify_raw_message(session, request_id, raw_payload)` (the raw NDJSON string from the message envelope's `payload` field).

Key implementation detail: when the adapter receives a `message` envelope from the sidecar, it extracts the `payload` (raw NDJSON string) and forwards it to Session as a binary via `notify_raw_message`. Session does `Jason.decode` + `CLI.Parser.parse_message`. No parsing in the adapter.

**Request ID mapping:** `request_id` is a `reference()` internally (from `make_ref()`) but must be serialized as a string for the WebSocket wire format. The adapter:
- Stores the current `request_id: reference()` in state (one at a time, matching Session's serial execution)
- Serializes it via `inspect(request_id)` when sending `query` envelopes to the sidecar
- Uses the stored `state.request_id` when receiving `message`/`done` envelopes (ignores the wire `request_id` string — it's only meaningful for the sidecar's bookkeeping)

This works because Session serializes queries — only one request is active at a time per adapter.

See design doc `Component 1: ClaudeCode.Adapter.Remote` for full lifecycle, state struct, and error handling.

**Step 3: Run tests and quality**

Run: `mix test test/claude_code/adapter/remote_test.exs && mix quality`
Expected: All pass

**Step 4: Commit**

```
git add lib/claude_code/adapter/remote.ex test/claude_code/adapter/remote_test.exs
git commit -m "feat: add Adapter.Remote — WebSocket client adapter"
```

---

### Task 6: Remote Adapter — Integration Test with Mock Sidecar

**Files:**
- Create: `test/support/mock_sidecar.ex`
- Create: `test/claude_code/adapter/remote_integration_test.exs`

**Step 1: Write mock sidecar**

A minimal Bandit WebSocket server that:
- Accepts connections with auth token validation
- Responds to `init` with `ready`
- Responds to `query` by sending canned raw NDJSON lines as `message` envelopes, then `done`

The mock does NOT parse CC messages — it sends raw strings in the `payload` field, exactly like the real sidecar would.

```elixir
# test/support/mock_sidecar.ex
defmodule ClaudeCode.Test.MockSidecar do
  @moduledoc false
  @behaviour WebSock

  alias ClaudeCode.Remote.Protocol

  def start(opts \\ []) do
    ndjson_lines = Keyword.get(opts, :ndjson_lines, [])
    test_pid = self()

    {:ok, pid} =
      Bandit.start_link(
        plug: {__MODULE__.Plug, test_pid: test_pid, ndjson_lines: ndjson_lines},
        port: 0, ip: :loopback, scheme: :http
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    {:ok, %{pid: pid, port: port}}
  end

  defmodule Plug do
    @moduledoc false
    @behaviour Plug
    def init(opts), do: opts
    def call(conn, opts), do: WebSockAdapter.upgrade(conn, ClaudeCode.Test.MockSidecar, opts, [])
  end

  @impl WebSock
  def init(opts), do: {:ok, %{test_pid: opts[:test_pid], ndjson_lines: opts[:ndjson_lines]}}

  @impl WebSock
  def handle_in({text, [opcode: :text]}, state) do
    {:ok, msg} = Protocol.decode(text)

    case msg.type do
      :init ->
        send(state.test_pid, {:sidecar_received, :init, msg})
        {:ok, ready} = Protocol.encode_ready("test-session-123")
        {:push, {:text, ready}, state}

      :query ->
        send(state.test_pid, {:sidecar_received, :query, msg.request_id})

        # Forward raw NDJSON lines as message envelopes
        frames =
          Enum.map(state.ndjson_lines, fn line ->
            {:ok, json} = Protocol.encode_message(msg.request_id, line)
            {:text, json}
          end)

        {:ok, done} = Protocol.encode_done(msg.request_id, "completed")
        {:push, frames ++ [{:text, done}], state}

      :stop ->
        send(state.test_pid, {:sidecar_received, :stop})
        {:stop, :normal, state}
    end
  end

  @impl WebSock
  def handle_info(_msg, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, _state), do: :ok
end
```

**Step 2: Write the integration test**

```elixir
# test/claude_code/adapter/remote_integration_test.exs
defmodule ClaudeCode.Adapter.RemoteIntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  alias ClaudeCode.Adapter.Remote
  alias ClaudeCode.Test.MockSidecar

  setup do
    # Raw NDJSON lines exactly as the CLI would emit
    assistant_line = ~s({"type":"assistant","message":{"id":"msg_001","type":"message","role":"assistant","content":[{"type":"text","text":"Hello!"}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"server_tool_use_input_tokens":0}},"session_id":"test-session-123"})

    result_line = ~s({"type":"result","subtype":"success","is_error":false,"duration_ms":100.0,"duration_api_ms":80.0,"num_turns":1,"result":"Hello!","session_id":"test-session-123","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"server_tool_use_input_tokens":0}})

    {:ok, server} = MockSidecar.start(ndjson_lines: [assistant_line, result_line])
    %{port: server.port}
  end

  test "full lifecycle: connect → init → query → receive messages → stop", %{port: port} do
    session = self()

    {:ok, adapter} =
      Remote.start_link(session, [
        url: "ws://localhost:#{port}/sessions",
        auth_token: "test-token",
        workspace_id: "test-workspace"
      ])

    # Provisioning → ready
    assert_receive {:adapter_status, :provisioning}, 1000
    assert_receive {:adapter_status, :ready}, 5000

    # Sidecar received init with protocol version
    assert_receive {:sidecar_received, :init, init_msg}, 1000
    assert init_msg.protocol_version == 1
    assert init_msg.workspace_id == "test-workspace"

    # Send query
    request_id = make_ref()
    :ok = Remote.send_query(adapter, request_id, "Say hello", [])

    # Receive raw messages (Session would parse these, but we're testing the adapter directly)
    assert_receive {:adapter_raw_message, ^request_id, _raw1}, 5000
    assert_receive {:adapter_raw_message, ^request_id, _raw2}, 5000

    # Stop
    :ok = Remote.stop(adapter)
  end
end
```

**Step 3: Run integration test**

Run: `mix test test/claude_code/adapter/remote_integration_test.exs --include integration`
Expected: All pass

**Step 4: Commit**

```
git add test/support/mock_sidecar.ex test/claude_code/adapter/remote_integration_test.exs
git commit -m "test: add Remote adapter integration test with mock sidecar"
```

---

## Phase 3: Sidecar Package

### Task 7: Scaffold `claude_code_sidecar` Mix Project

**Files:**
- Create: `sidecar/mix.exs`
- Create: `sidecar/lib/claude_code/sidecar.ex`
- Create: `sidecar/lib/claude_code/sidecar/application.ex`
- Create: `sidecar/lib/claude_code/sidecar/router.ex`
- Create: `sidecar/config/config.exs`
- Create: `sidecar/config/runtime.exs`
- Create: `sidecar/config/dev.exs`
- Create: `sidecar/config/test.exs`
- Create: `sidecar/.formatter.exs`
- Create: `sidecar/test/test_helper.exs`

The sidecar depends on the full `claude_code` package — it uses `Adapter.Local` for CLI lifecycle and control protocol, plus `Remote.Protocol` for WebSocket envelope encoding.

Key dependencies in `sidecar/mix.exs`:

```elixir
defp deps do
  [
    {:claude_code, path: ".."},
    {:bandit, "~> 1.0"},
    {:websock_adapter, "~> 0.5"}
  ]
end
```

**Step 1: Create all scaffold files**

**Step 2: Verify compilation**

Run: `cd sidecar && mix deps.get && mix compile`
Expected: Clean compile (SessionHandler not yet created → warning is fine)

**Step 3: Commit**

```
git add sidecar/
git commit -m "feat: scaffold claude_code_sidecar mix project"
```

---

### Task 8: Sidecar — WorkspaceManager

**Files:**
- Create: `sidecar/lib/claude_code/sidecar/workspace_manager.ex`
- Create: `sidecar/test/claude_code/sidecar/workspace_manager_test.exs`

**Step 1: Write tests**

Tests for `ensure_workspace/2`: creates directory, idempotent, rejects path traversal (`../`, `/`), rejects empty string.

**Step 2: Implement**

Simple module: `ensure_workspace(root, workspace_id)` validates the ID, creates `Path.join(root, workspace_id)`, returns `{:ok, path}`.

**Step 3: Run tests**

Run: `cd sidecar && mix test test/claude_code/sidecar/workspace_manager_test.exs`
Expected: All pass

**Step 4: Commit**

```
git add sidecar/
git commit -m "feat: add WorkspaceManager for sidecar workspace isolation"
```

---

### Task 9: Sidecar — SessionHandler (Adapter.Local Bridge)

**Files:**
- Create: `sidecar/lib/claude_code/sidecar/session_handler.ex`
- Create: `sidecar/test/claude_code/sidecar/session_handler_test.exs`

This is the core of the sidecar. It's a WebSock handler that bridges `Adapter.Local` to the WebSocket:
1. Receives `init` → creates workspace, starts `Adapter.Local` with itself as session process, waits for `{:adapter_status, :ready}`, sends `ready`
2. Receives `query` → calls `Adapter.Local.send_query/4`
3. Receives `{:adapter_raw_message, request_id, decoded_map}` from `Adapter.Local` → re-encodes to JSON, forwards as `message` envelope
4. Detects `decoded_map["type"] == "result"` → sends `done` envelope
5. Receives `{:adapter_error, request_id, reason}` → sends `error` envelope
6. WebSocket disconnect → calls `Adapter.Local.stop/1`

**Step 1: Write tests**

Test the bridge behavior: send init, verify ready; send query, verify CC messages forwarded. Use a mock CLI script (shell script that emits canned NDJSON) set via `:cli_path` option so `Adapter.Local` runs the mock instead of the real CLI.

**Step 2: Implement SessionHandler**

Key implementation — the Adapter.Local notification handlers:

```elixir
@impl WebSock
def init(opts) do
  {:ok, %{
    adapter_pid: nil,
    request_id: nil,
    workspace_id: nil,
    workspaces_root: opts[:workspaces_root] || "/workspaces"
  }}
end

@impl WebSock
def handle_in({text, [opcode: :text]}, state) do
  {:ok, msg} = Protocol.decode(text)

  case msg.type do
    :init -> handle_init(msg, state)
    :query -> handle_query(msg, state)
    :stop -> handle_stop(state)
    :interrupt -> handle_interrupt(state)
  end
end

defp handle_init(msg, state) do
  {:ok, workspace_path} = WorkspaceManager.ensure_workspace(
    state.workspaces_root, msg.workspace_id
  )

  # Build adapter opts from session_opts, setting cwd to workspace
  adapter_opts =
    msg.session_opts
    |> build_adapter_opts(workspace_path, msg.resume)
    |> filter_non_serializable_opts()

  {:ok, adapter_pid} = ClaudeCode.Adapter.Local.start_link(self(), adapter_opts)

  # Adapter.Local will send {:adapter_status, :ready} via handle_info
  {:ok, %{state | adapter_pid: adapter_pid, workspace_id: msg.workspace_id}}
end

defp handle_query(msg, state) do
  request_id = make_ref()
  :ok = ClaudeCode.Adapter.Local.send_query(
    state.adapter_pid, request_id, msg.prompt, Enum.to_list(msg.opts || %{})
  )
  {:ok, %{state | request_id: request_id, wire_request_id: msg.request_id}}
end

# Adapter.Local sends these as regular Erlang messages to our process:
@impl WebSock
def handle_info({:adapter_status, :ready}, state) do
  {:ok, json} = Protocol.encode_ready(state.workspace_id)
  {:push, {:text, json}, state}
end

def handle_info({:adapter_raw_message, _request_id, decoded_map}, state) do
  # Re-encode the decoded map to JSON for wire transport
  raw_json = Jason.encode!(decoded_map)
  {:ok, msg_json} = Protocol.encode_message(state.wire_request_id, raw_json)
  frames = [{:text, msg_json}]

  # Detect result → send done envelope
  frames =
    if decoded_map["type"] == "result" do
      {:ok, done_json} = Protocol.encode_done(state.wire_request_id, "completed")
      frames ++ [{:text, done_json}]
    else
      frames
    end

  {:push, frames, state}
end

def handle_info({:adapter_error, _request_id, reason}, state) do
  {:ok, json} = Protocol.encode_error(
    state.wire_request_id, "session_error", inspect(reason)
  )
  {:push, {:text, json}, state}
end

def handle_info({:adapter_status, {:error, reason}}, state) do
  {:ok, json} = Protocol.encode_error(nil, "init_error", inspect(reason))
  {:push, {:text, json}, state}
end
```

Note: `filter_non_serializable_opts/1` strips Elixir function hooks and SDK MCP servers from the session opts, since these cannot work in remote mode (see Limitations in design doc).

**Step 3: Run tests**

Run: `cd sidecar && mix test`
Expected: All pass

**Step 4: Commit**

```
git add sidecar/
git commit -m "feat: add SessionHandler — Adapter.Local to WebSocket bridge"
```

---

## Phase 4: Quality & Verification

### Task 10: Quality Checks — claude_code

**Step 1:** Run `mix quality`
**Step 2:** Run `mix test`
**Step 3:** Fix any issues, commit

---

### Task 11: Quality Checks — claude_code_sidecar

**Step 1:** Run `cd sidecar && mix quality`
**Step 2:** Run `cd sidecar && mix test`
**Step 3:** Fix any issues, commit

---

### Task 12: End-to-End Integration Test

**Files:**
- Create: `test/claude_code/remote/end_to_end_test.exs`

A test that starts the real sidecar (Bandit) in the test process, connects `Adapter.Remote` to it, and verifies the full flow through `ClaudeCode.Session`. Uses a mock CLI script on the sidecar side (via `:cli_path` option to `Adapter.Local`) that emits canned NDJSON.

This validates the complete path:
```
Session → Adapter.Remote → WebSocket → Sidecar.SessionHandler → Adapter.Local → Port (mock CLI)
  → decoded map → re-encoded JSON → WebSocket → Adapter.Remote → notify_raw_message → Session parses → subscriber
```

**Step 1:** Write mock CLI script (shell script that reads stdin, emits NDJSON lines including initialize handshake response)
**Step 2:** Write test starting sidecar + session with remote adapter, using `:cli_path` to point Adapter.Local at the mock script
**Step 3:** Verify messages arrive as parsed structs at the subscriber
**Step 4:** Commit

---

## Implementation Notes

1. **Mint.WebSocket is process-less** — all state is in `Mint.HTTP.t()` and `Mint.WebSocket.t()` structs. TCP/SSL messages arrive as regular Erlang messages to the GenServer's `handle_info/2`.

2. **Request ID mapping** — `request_id` is a `reference()` internally but serialized to string via `inspect/1` for the wire. The adapter maps back using `state.request_id`.

3. **Raw NDJSON passthrough** — The sidecar's `message` envelope has a `payload` field containing the raw NDJSON string (re-encoded from `Adapter.Local`'s decoded map). The adapter extracts it and sends to Session as a binary. Session does `Jason.decode` + `CLI.Parser.parse_message`. No parsing in the adapter.

4. **ResultMessage detection** — Both Adapter.Local and the sidecar peek at the decoded map to detect `json["type"] == "result"` without struct parsing. Adapter.Local resets its `current_request`; the sidecar sends a `done` envelope. Session also auto-detects ResultMessage when parsing raw messages.

5. **`Jason` module** — Use `Jason` consistently throughout the codebase (matching the existing convention). All new code uses `Jason.encode!/1` and `Jason.decode/1`.

6. **Sidecar module naming** — Package is `claude_code_sidecar` on Hex, module namespace is `ClaudeCode.Sidecar.*` (like `phoenix_live_view` → `Phoenix.LiveView`). Files under `sidecar/lib/claude_code/sidecar/`.

7. **Sidecar uses Adapter.Local** — It depends on the full `claude_code` package and uses `Adapter.Local` to manage the CLI subprocess. This reuses the complete CLI lifecycle: binary resolution, Port management, initialize handshake, hook callbacks, and control protocol handling. The sidecar itself only bridges between `Adapter.Local` notifications and WebSocket envelopes.

8. **Protocol version validation** — The sidecar's `Protocol.decode/1` rejects `init` messages with unsupported protocol versions. This is enforced at decode time, not just declared.

9. **TLS config** — `transport_opts(:https)` uses `:public_key.cacerts_get()` (OTP 25+). For older OTP, use the `castore` package.

10. **Re-encoding on sidecar** — `Adapter.Local` decodes CLI stdout to maps (via `Jason.decode` in `process_line`). The sidecar re-encodes these maps to JSON strings for WebSocket transport (via `Jason.encode!`). This is one extra encode per message — negligible compared to LLM API latency. The alternative (preserving raw strings through Adapter.Local) would complicate the control message classification logic.

11. **Remote mode limitations** — Elixir function hooks, SDK MCP servers (in-process), and `can_use_tool` callbacks are not supported in remote mode because Elixir functions cannot be serialized over the wire. The sidecar's `filter_non_serializable_opts/1` strips these from session opts. See design doc "Remote Adapter Limitations" section.
