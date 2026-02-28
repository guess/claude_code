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

**Step 1: Write the failing tests**

Add tests to `session_test.exs` that send raw JSON directly to Session via the new message tuple and verify parsing and delivery. The stub blocks forever so the Test adapter never sends its own messages or `notify_done` — we bypass it entirely to test the raw message path.

```elixir
describe "raw message handling" do
  # Helper: a stub that blocks forever, keeping the request active.
  # send_query is a GenServer.cast, so it returns :ok immediately;
  # the blocking happens in the Test adapter's process, not Session's.
  defp blocking_stub do
    fn _query, _opts ->
      receive do
        :never -> []
      end
    end
  end

  # Reusable raw result map matching real CLI output shape
  defp raw_result_map(text \\ "Hello from raw!") do
    %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "duration_ms" => 100.0,
      "duration_api_ms" => 80.0,
      "num_turns" => 1,
      "result" => text,
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
  end

  test "parses and delivers raw JSON map from adapter" do
    ClaudeCode.Test.stub(ClaudeCode, blocking_stub())
    {:ok, session} = Session.start_link(adapter: @adapter)

    {:ok, request_id} = GenServer.call(session, {:query_stream, "test", []})

    # Send raw map directly (simulating what Adapter.Local would do)
    send(session, {:adapter_raw_message, request_id, raw_result_map()})

    # Should receive parsed ResultMessage
    {:message, message} = GenServer.call(session, {:receive_next, request_id})
    assert %ResultMessage{} = message
    assert message.result == "Hello from raw!"

    # ResultMessage should auto-trigger done (request completed)
    assert :done = GenServer.call(session, {:receive_next, request_id})
  end

  test "parses raw JSON binary string from adapter" do
    ClaudeCode.Test.stub(ClaudeCode, blocking_stub())
    {:ok, session} = Session.start_link(adapter: @adapter)

    {:ok, request_id} = GenServer.call(session, {:query_stream, "test", []})

    # Send raw JSON binary (simulating what Adapter.Remote would do)
    raw_json = Jason.encode!(raw_result_map("Hello from binary!"))
    send(session, {:adapter_raw_message, request_id, raw_json})

    {:message, message} = GenServer.call(session, {:receive_next, request_id})
    assert %ResultMessage{} = message
    assert message.result == "Hello from binary!"
    assert :done = GenServer.call(session, {:receive_next, request_id})
  end

  test "handles non-result raw messages without completing request" do
    ClaudeCode.Test.stub(ClaudeCode, blocking_stub())
    {:ok, session} = Session.start_link(adapter: @adapter)

    {:ok, request_id} = GenServer.call(session, {:query_stream, "test", []})

    # Send a raw assistant message (NOT a result)
    raw_assistant = %{
      "type" => "assistant",
      "message" => %{
        "id" => "msg_001",
        "type" => "message",
        "role" => "assistant",
        "content" => [%{"type" => "text", "text" => "Working on it..."}],
        "model" => "claude-sonnet-4-20250514",
        "stop_reason" => nil,
        "stop_sequence" => nil,
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 5,
          "cache_creation_input_tokens" => 0,
          "cache_read_input_tokens" => 0,
          "server_tool_use_input_tokens" => 0
        }
      },
      "session_id" => "test-session"
    }

    send(session, {:adapter_raw_message, request_id, raw_assistant})

    # Should receive parsed AssistantMessage
    {:message, message} = GenServer.call(session, {:receive_next, request_id})
    assert %AssistantMessage{} = message

    # Request should still be active (not done), so sending result completes it
    send(session, {:adapter_raw_message, request_id, raw_result_map()})
    {:message, result} = GenServer.call(session, {:receive_next, request_id})
    assert %ResultMessage{} = result
    assert :done = GenServer.call(session, {:receive_next, request_id})
  end

  test "discards raw message for unknown request_id" do
    ClaudeCode.Test.stub(ClaudeCode, blocking_stub())
    {:ok, session} = Session.start_link(adapter: @adapter)

    # Send raw message with a request_id that doesn't exist
    bogus_ref = make_ref()
    send(session, {:adapter_raw_message, bogus_ref, raw_result_map()})

    # Give Session time to process (it should discard silently)
    Process.sleep(50)
    assert Process.alive?(session)
  end

  test "logs warning for unparseable raw message" do
    ClaudeCode.Test.stub(ClaudeCode, blocking_stub())
    {:ok, session} = Session.start_link(adapter: @adapter)

    {:ok, request_id} = GenServer.call(session, {:query_stream, "test", []})

    # Send invalid binary — Session should log and discard
    send(session, {:adapter_raw_message, request_id, "not valid json"})

    Process.sleep(50)
    assert Process.alive?(session)
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

Add to `lib/claude_code/session.ex`, in the `handle_info` clauses (before the existing `handle_info({:adapter_message, ...})` at line 216):

**Important:** Do NOT call `handle_info({:adapter_done, ...}, state)` recursively — the return value would be discarded, losing state changes. Call `complete_request/3` directly instead.

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

        # Auto-detect ResultMessage → complete the request directly.
        # This replaces the separate notify_done that parsed-message adapters use.
        if match?(%ClaudeCode.Message.ResultMessage{}, message) do
          {:noreply, complete_request(request_id, updated_request, state)}
        else
          {:noreply, state}
        end
    end
  else
    {:error, reason} ->
      Logger.warning("Failed to parse raw message: #{inspect(reason)}")
      {:noreply, state}
  end
end

defp decode_if_binary(raw) when is_binary(raw), do: Jason.decode(raw)
defp decode_if_binary(raw) when is_map(raw), do: {:ok, raw}
```

Note: `complete_request/3` (defined at line 434) handles subscriber notification, status update, and queue processing — same as the `{:adapter_done, ...}` handler uses.

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

**Step 2: Modify `handle_sdk_message/2` (local.ex lines 506–526)**

Replace the current implementation that parses and notifies with raw forwarding:

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

Also remove the `alias ClaudeCode.Message.ResultMessage` if it's only used here, and remove the `alias ClaudeCode.CLI.Parser` if no longer needed in the adapter. Run `grep -n 'ResultMessage\|Parser' lib/claude_code/adapter/local.ex` to check for other uses before removing aliases.

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
      assert {:ok, %{type: :control}} = Protocol.decode(~s({"type":"control","request_id":"r","subtype":"can_use_tool","params":{}}))
      assert {:ok, %{type: :control_response}} = Protocol.decode(~s({"type":"control_response","request_id":"r","response":{}}))
      assert {:ok, %{type: :stop}} = Protocol.decode(~s({"type":"stop"}))
      assert {:ok, %{type: :interrupt}} = Protocol.decode(~s({"type":"interrupt"}))
    end

    test "decodes control with can_use_tool subtype" do
      json = ~s({"type":"control","request_id":"r","subtype":"can_use_tool","params":{"tool_name":"Bash","tool_input":{"command":"ls"}}})
      {:ok, decoded} = Protocol.decode(json)
      assert decoded.type == :control
      assert decoded.subtype == "can_use_tool"
      assert decoded.params["tool_name"] == "Bash"
    end

    test "decodes control_response with allowed field" do
      json = ~s({"type":"control_response","request_id":"r","response":{"allowed":true}})
      {:ok, decoded} = Protocol.decode(json)
      assert decoded.type == :control_response
      assert decoded.response["allowed"] == true
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

  describe "validate_config/1" do
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

    test "generates workspace_id if not provided" do
      assert {:ok, c1} = Remote.validate_config(url: "wss://x.com/s", auth_token: "t")
      assert {:ok, c2} = Remote.validate_config(url: "wss://x.com/s", auth_token: "t")
      assert c1[:workspace_id] != c2[:workspace_id]
    end

    test "preserves explicit workspace_id" do
      assert {:ok, config} = Remote.validate_config(url: "wss://x.com/s", auth_token: "t", workspace_id: "my-ws")
      assert config[:workspace_id] == "my-ws"
    end
  end

  describe "parse_url/1" do
    test "parses wss with default port" do
      assert {:ok, :https, "example.com", 443, "/sessions"} = Remote.parse_url("wss://example.com/sessions")
    end

    test "parses ws with explicit port" do
      assert {:ok, :http, "localhost", 4040, "/s"} = Remote.parse_url("ws://localhost:4040/s")
    end

    test "defaults path to / when absent" do
      assert {:ok, :https, "example.com", 443, "/"} = Remote.parse_url("wss://example.com")
    end

    test "rejects http scheme" do
      assert {:error, _} = Remote.parse_url("http://example.com")
    end

    test "rejects https scheme" do
      assert {:error, _} = Remote.parse_url("https://example.com")
    end
  end

  describe "heartbeat constants" do
    test "heartbeat interval is 30 seconds" do
      assert Remote.heartbeat_interval_ms() == 30_000
    end

    test "pong timeout is 10 seconds" do
      assert Remote.pong_timeout_ms() == 10_000
    end
  end
end
```

**Step 2: Run tests to verify failure**

Run: `mix test test/claude_code/adapter/remote_test.exs`
Expected: Compilation error — module not found

**Step 3: Write complete implementation**

```elixir
# lib/claude_code/adapter/remote.ex
defmodule ClaudeCode.Adapter.Remote do
  @moduledoc """
  WebSocket-based adapter for remote CC session execution.

  Connects to a sidecar service over WebSocket and forwards queries
  and messages between the local Session and the remote CC CLI process.

  ## Usage

      {:ok, session} = ClaudeCode.start_link(
        adapter: {ClaudeCode.Adapter.Remote,
          url: "wss://agent-runner.example.com/sessions",
          auth_token: "secret-token",
          workspace_id: "agent_abc123"
        },
        model: "sonnet"
      )

  ## How It Works

  - `start_link/2` validates config, connects via Mint.HTTP, upgrades to WebSocket
  - Sends a protocol `init` message with session options and workspace ID
  - Waits for a `ready` ack from the sidecar (with configurable timeout)
  - `send_query/4` sends query envelopes; receives `message` envelopes with raw NDJSON
  - Forwards raw NDJSON payloads to Session via `notify_raw_message/3` — no parsing in adapter
  - Session handles all CC message parsing via `CLI.Parser`

  ## Request ID Mapping

  `request_id` is a `reference()` internally but must be serialized for the wire.
  Since Session serializes queries (one active at a time per adapter), the adapter
  stores the current `request_id` in state and uses it for all incoming messages,
  ignoring the wire request ID from the sidecar.
  """

  use GenServer
  require Logger

  @behaviour ClaudeCode.Adapter

  alias ClaudeCode.Adapter
  alias ClaudeCode.Remote.Protocol

  @default_connect_timeout 10_000
  @default_init_timeout 30_000

  @heartbeat_interval_ms 30_000
  @pong_timeout_ms 10_000

  @doc false
  def heartbeat_interval_ms, do: @heartbeat_interval_ms
  @doc false
  def pong_timeout_ms, do: @pong_timeout_ms

  defstruct [
    :session,
    :conn,
    :websocket,
    :request_ref,
    :request_id,
    :remote_session_id,
    :config,
    :init_timer,
    :heartbeat_timer,
    :pong_timer,
    missed_pongs: 0,
    status: :disconnected
  ]

  # ============================================================================
  # Config Validation
  # ============================================================================

  @config_schema [
    url: [type: :string, required: true, doc: "WebSocket URL (ws:// or wss://)"],
    auth_token: [type: :string, required: true, doc: "Bearer token for authentication"],
    workspace_id: [type: :string, doc: "Workspace directory name on the sidecar"],
    connect_timeout: [type: :pos_integer, default: @default_connect_timeout],
    init_timeout: [type: :pos_integer, default: @default_init_timeout],
    session_opts: [type: :map, default: %{}, doc: "Session options to forward to sidecar"]
  ]

  @spec validate_config(keyword()) :: {:ok, keyword()} | {:error, term()}
  def validate_config(config) do
    case NimbleOptions.validate(config, @config_schema) do
      {:ok, validated} ->
        validated =
          Keyword.put_new_lazy(validated, :workspace_id, fn ->
            "ws_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
          end)

        {:ok, validated}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  @spec parse_url(String.t()) ::
          {:ok, :http | :https, String.t(), pos_integer(), String.t()} | {:error, term()}
  def parse_url(url) do
    uri = URI.parse(url)

    case uri.scheme do
      "wss" -> {:ok, :https, uri.host, uri.port || 443, uri.path || "/"}
      "ws" -> {:ok, :http, uri.host, uri.port || 80, uri.path || "/"}
      other -> {:error, {:invalid_scheme, other, "expected ws:// or wss://"}}
    end
  end

  # ============================================================================
  # Adapter Behaviour
  # ============================================================================

  @impl ClaudeCode.Adapter
  def start_link(session, config) do
    case validate_config(config) do
      {:ok, validated} ->
        GenServer.start_link(__MODULE__, {session, validated})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl ClaudeCode.Adapter
  def send_query(adapter, request_id, prompt, opts) do
    GenServer.call(adapter, {:query, request_id, prompt, opts})
  end

  @impl ClaudeCode.Adapter
  def health(adapter) do
    GenServer.call(adapter, :health)
  end

  @impl ClaudeCode.Adapter
  def stop(adapter) do
    GenServer.call(adapter, :stop)
  catch
    :exit, _ -> :ok
  end

  @impl ClaudeCode.Adapter
  def interrupt(adapter) do
    GenServer.cast(adapter, :interrupt)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({session, config}) do
    Process.link(session)

    state = %__MODULE__{
      session: session,
      config: config
    }

    Adapter.notify_status(session, :provisioning)
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        # WebSocket upgrade request sent — wait for HTTP 101 + headers via handle_info.
        # Init message is sent after WebSocket is established (in handle_response for :headers).
        timer = Process.send_after(self(), :init_timeout, state.config[:init_timeout])
        {:noreply, %{new_state | init_timer: timer, status: :connecting}}

      {:error, reason} ->
        Adapter.notify_status(state.session, {:error, reason})
        {:stop, reason, state}
    end
  end

  @impl GenServer
  def handle_call({:query, request_id, prompt, opts}, _from, %{status: :ready} = state) do
    wire_request_id = inspect(request_id)

    serializable_opts =
      opts
      |> Keyword.drop([:session_id])
      |> serialize_query_opts()

    {:ok, json} =
      Protocol.encode_query(%{
        request_id: wire_request_id,
        prompt: prompt,
        opts: serializable_opts
      })

    case send_frame(state, {:text, json}) do
      {:ok, new_state} ->
        {:reply, :ok, %{new_state | request_id: request_id}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query, _request_id, _prompt, _opts}, _from, state) do
    {:reply, {:error, {:not_ready, state.status}}, state}
  end

  def handle_call(:health, _from, state) do
    health =
      case state.status do
        :ready -> :healthy
        :connecting -> :degraded
        _ -> {:unhealthy, state.status}
      end

    {:reply, health, state}
  end

  def handle_call(:stop, _from, state) do
    new_state = do_stop(state)
    {:stop, :normal, :ok, new_state}
  end

  @impl GenServer
  def handle_cast(:interrupt, state) do
    {:ok, json} = Protocol.encode_interrupt()

    case send_frame(state, {:text, json}) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn}
        handle_responses(responses, state)

      {:error, conn, reason, _responses} ->
        state = %{state | conn: conn, status: :disconnected}

        if state.request_id do
          Adapter.notify_error(state.session, state.request_id, {:websocket_error, reason})
        end

        {:noreply, state}

      :unknown ->
        handle_non_ws_message(message, state)
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    do_stop(state)
    :ok
  end

  # ============================================================================
  # Private — Connection
  # ============================================================================

  defp do_connect(state) do
    config = state.config

    with {:ok, scheme, host, port, path} <- parse_url(config[:url]),
         {:ok, conn} <-
           Mint.HTTP.connect(scheme, host, port,
             transport_opts: transport_opts(scheme),
             protocols: [:http1]
           ),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(scheme, conn, path, [
             {"authorization", "Bearer #{config[:auth_token]}"}
           ]) do
      {:ok, %{state | conn: conn, request_ref: ref}}
    end
  end

  defp transport_opts(:https) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp transport_opts(:http), do: []

  defp send_init(state) do
    {:ok, json} =
      Protocol.encode_init(%{
        session_opts: state.config[:session_opts],
        workspace_id: state.config[:workspace_id],
        resume: state.remote_session_id
      })

    send_frame(state, {:text, json})
  end

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         {:ok, conn} <- Mint.HTTP.stream_request_body(state.conn, state.request_ref, data) do
      {:ok, %{state | conn: conn, websocket: websocket}}
    end
  end

  defp do_stop(state) do
    if state.conn && state.status in [:connecting, :ready] do
      with {:ok, json} <- Protocol.encode_stop(),
           {:ok, state} <- send_frame(state, {:text, json}),
           {:ok, state} <- send_frame(state, :close) do
        state
      else
        _ -> state
      end
    else
      state
    end
  end

  # ============================================================================
  # Private — Response Handling (Mint.WebSocket.stream responses)
  # ============================================================================

  defp handle_responses([], state), do: {:noreply, state}

  defp handle_responses([response | rest], state) do
    case handle_response(response, state) do
      {:ok, new_state} -> handle_responses(rest, new_state)
      {:error, new_state} -> {:noreply, new_state}
      {:stop, reason, new_state} -> {:stop, reason, new_state}
    end
  end

  defp handle_response({:status, ref, status}, %{request_ref: ref} = state) do
    if status != 101 do
      Logger.error("WebSocket upgrade failed with HTTP #{status}")
      {:error, %{state | status: {:error, {:http_status, status}}}}
    else
      {:ok, state}
    end
  end

  defp handle_response({:headers, ref, headers}, %{request_ref: ref} = state) do
    case Mint.WebSocket.new(state.conn, ref, 101, headers) do
      {:ok, conn, websocket} ->
        state = %{state | conn: conn, websocket: websocket}

        # WebSocket established — send init message immediately
        case send_init(state) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:error, %{state | status: {:error, reason}}}
        end

      {:error, conn, reason} ->
        {:error, %{state | conn: conn, status: {:error, reason}}}
    end
  end

  defp handle_response({:data, ref, data}, %{request_ref: ref} = state) do
    case Mint.WebSocket.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        state = %{state | websocket: websocket}
        handle_frames(frames, state)

      {:error, websocket, reason} ->
        {:error, %{state | websocket: websocket, status: {:error, reason}}}
    end
  end

  defp handle_response({:done, ref}, %{request_ref: ref} = state) do
    state = %{state | status: :disconnected}

    if state.request_id do
      Adapter.notify_error(state.session, state.request_id, :connection_closed)
    end

    {:ok, state}
  end

  defp handle_response(_other, state), do: {:ok, state}

  # ============================================================================
  # Private — WebSocket Frame Handling
  # ============================================================================

  defp handle_frames([], state), do: {:ok, state}

  defp handle_frames([frame | rest], state) do
    case handle_frame(frame, state) do
      {:ok, new_state} -> handle_frames(rest, new_state)
      other -> other
    end
  end

  defp handle_frame({:text, text}, state) do
    case Protocol.decode(text) do
      {:ok, %{type: :ready} = msg} ->
        if state.init_timer, do: Process.cancel_timer(state.init_timer)
        Adapter.notify_status(state.session, :ready)
        # Start heartbeat loop now that connection is established
        heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
        {:ok, %{state | status: :ready, remote_session_id: msg.session_id, init_timer: nil, heartbeat_timer: heartbeat_timer}}

      {:ok, %{type: :message} = msg} ->
        # Forward raw NDJSON payload to Session — no parsing here.
        # Session will Jason.decode + CLI.Parser.parse_message.
        if state.request_id do
          Adapter.notify_raw_message(state.session, state.request_id, msg.payload)
        end

        {:ok, state}

      {:ok, %{type: :done}} ->
        # Session auto-detects ResultMessage for completion via raw message handler.
        # Clear request_id so we can accept the next query.
        {:ok, %{state | request_id: nil}}

      {:ok, %{type: :error} = msg} ->
        if state.request_id do
          Adapter.notify_error(
            state.session,
            state.request_id,
            {:remote_error, msg.code, msg.details}
          )
        end

        {:ok, %{state | request_id: nil}}

      {:error, reason} ->
        Logger.warning("Failed to decode protocol message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp handle_frame({:ping, data}, state) do
    case send_frame(state, {:pong, data}) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, _reason} -> {:ok, state}
    end
  end

  defp handle_frame({:pong, _data}, state) do
    # Pong received — cancel pong timeout, reset missed count
    if state.pong_timer, do: Process.cancel_timer(state.pong_timer)
    {:ok, %{state | pong_timer: nil, missed_pongs: 0}}
  end

  defp handle_frame({:close, _code, _reason}, state) do
    state = %{state | status: :disconnected}

    if state.request_id do
      Adapter.notify_error(state.session, state.request_id, :connection_closed)
    end

    {:ok, state}
  end

  defp handle_frame(_other, state), do: {:ok, state}

  # ============================================================================
  # Private — Non-WebSocket Messages
  # ============================================================================

  defp handle_non_ws_message(:init_timeout, %{status: :connecting} = state) do
    Adapter.notify_status(state.session, {:error, :init_timeout})
    {:stop, :init_timeout, state}
  end

  defp handle_non_ws_message(:init_timeout, state) do
    # Already connected, ignore stale timer
    {:noreply, state}
  end

  defp handle_non_ws_message(:heartbeat, %{status: :ready} = state) do
    case send_frame(state, :ping) do
      {:ok, new_state} ->
        # Schedule pong timeout check and next heartbeat
        pong_timer = Process.send_after(self(), :pong_timeout, @pong_timeout_ms)
        heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
        {:noreply, %{new_state | pong_timer: pong_timer, heartbeat_timer: heartbeat_timer}}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  defp handle_non_ws_message(:heartbeat, state) do
    # Not ready, skip heartbeat
    {:noreply, state}
  end

  defp handle_non_ws_message(:pong_timeout, state) do
    missed = state.missed_pongs + 1

    if missed >= 2 do
      # Two consecutive missed pongs — treat as disconnect
      Logger.warning("WebSocket heartbeat failed: #{missed} missed pongs, disconnecting")

      if state.request_id do
        Adapter.notify_error(state.session, state.request_id, :heartbeat_timeout)
      end

      {:noreply, %{state | status: :disconnected, missed_pongs: missed}}
    else
      {:noreply, %{state | missed_pongs: missed}}
    end
  end

  defp handle_non_ws_message(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private — Option Serialization
  # ============================================================================

  # Converts Elixir-native query options to JSON-serializable format.
  # Atoms become strings, keyword lists become maps.
  defp serialize_query_opts(opts) do
    opts
    |> Enum.map(fn {k, v} -> {to_string(k), serialize_value(v)} end)
    |> Map.new()
  end

  defp serialize_value(v) when is_atom(v), do: to_string(v)
  defp serialize_value(v) when is_list(v), do: Enum.map(v, &serialize_value/1)
  defp serialize_value(%{} = v), do: Map.new(v, fn {k, val} -> {to_string(k), serialize_value(val)} end)
  defp serialize_value(v), do: v
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/remote_test.exs`
Expected: All pass

**Step 5: Run quality**

Run: `mix quality`
Expected: All pass

**Step 6: Commit**

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
- Validates auth token on connection (rejects invalid tokens with 401)
- Responds to `init` with `ready`
- Responds to `query` by sending canned raw NDJSON lines as `message` envelopes, then `done`

The mock does NOT parse CC messages — it sends raw strings in the `payload` field, exactly like the real sidecar would.

```elixir
# test/support/mock_sidecar.ex
defmodule ClaudeCode.Test.MockSidecar do
  @moduledoc false
  @behaviour WebSock

  alias ClaudeCode.Remote.Protocol

  @default_auth_token "test-token"

  def start(opts \\ []) do
    ndjson_lines = Keyword.get(opts, :ndjson_lines, [])
    auth_token = Keyword.get(opts, :auth_token, @default_auth_token)
    test_pid = self()

    {:ok, pid} =
      Bandit.start_link(
        plug: {__MODULE__.Plug, test_pid: test_pid, ndjson_lines: ndjson_lines, auth_token: auth_token},
        port: 0, ip: :loopback, scheme: :http
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    {:ok, %{pid: pid, port: port}}
  end

  defmodule Plug do
    @moduledoc false
    @behaviour Plug
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      expected_token = opts[:auth_token]

      case Plug.Conn.get_req_header(conn, "authorization") do
        ["Bearer " <> ^expected_token] ->
          WebSockAdapter.upgrade(conn, ClaudeCode.Test.MockSidecar, opts, [])

        _ ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(401, "Unauthorized")
      end
    end
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

      :interrupt ->
        send(state.test_pid, {:sidecar_received, :interrupt})
        {:ok, state}
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

  test "health returns :healthy when connected", %{port: port} do
    session = self()

    {:ok, adapter} =
      Remote.start_link(session, [
        url: "ws://localhost:#{port}/sessions",
        auth_token: "test-token"
      ])

    assert_receive {:adapter_status, :ready}, 5000
    assert Remote.health(adapter) == :healthy
    :ok = Remote.stop(adapter)
  end

  test "rejects connection with invalid auth token", %{port: port} do
    session = self()

    # Use wrong token — MockSidecar returns 401
    result =
      Remote.start_link(session, [
        url: "ws://localhost:#{port}/sessions",
        auth_token: "wrong-token"
      ])

    case result do
      {:ok, _adapter} ->
        # Adapter started but will fail during WebSocket upgrade
        assert_receive {:adapter_status, :provisioning}, 1000
        assert_receive {:adapter_status, {:error, _reason}}, 5000

      {:error, _reason} ->
        # Connection rejected outright
        :ok
    end
  end

  test "fails with init_timeout when sidecar never sends ready" do
    # Start a server that accepts connections but never sends ready
    {:ok, pid} =
      Bandit.start_link(
        plug: {ClaudeCode.Test.MockSidecar.Plug,
          test_pid: self(),
          ndjson_lines: [],
          auth_token: "test-token"},
        port: 0, ip: :loopback, scheme: :http
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)

    # Override init handler to NOT send ready (we can't easily do this with the
    # current MockSidecar, so we test with a very short timeout instead)
    session = self()

    {:ok, adapter} =
      Remote.start_link(session, [
        url: "ws://localhost:#{port}/sessions",
        auth_token: "test-token",
        init_timeout: 100
      ])

    assert_receive {:adapter_status, :provisioning}, 1000

    # Either gets ready (mock sends it fast) or times out
    receive do
      {:adapter_status, :ready} -> :ok = Remote.stop(adapter)
      {:adapter_status, {:error, :init_timeout}} -> :ok
    after
      5000 -> flunk("Expected status change within 5s")
    end
  end

  test "connection refused when no server running" do
    session = self()

    # Connect to a port where nothing is listening
    result =
      Remote.start_link(session, [
        url: "ws://localhost:19999/sessions",
        auth_token: "test-token"
      ])

    case result do
      {:ok, _adapter} ->
        assert_receive {:adapter_status, :provisioning}, 1000
        assert_receive {:adapter_status, {:error, _}}, 5000

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  test "query returns error when not ready" do
    # Start without a server — adapter won't reach :ready state
    session = self()
    {:ok, server} = MockSidecar.start(ndjson_lines: [])
    port = server.port

    {:ok, adapter} =
      Remote.start_link(session, [
        url: "ws://localhost:#{port}/sessions",
        auth_token: "test-token"
      ])

    # Don't wait for ready — try to query immediately
    request_id = make_ref()
    # May get {:error, {:not_ready, _}} if not yet ready, or :ok if ready
    case Remote.send_query(adapter, request_id, "test", []) do
      :ok -> :ok
      {:error, {:not_ready, _}} -> :ok
    end

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
- Create: `sidecar/lib/claude_code/sidecar/session_registry.ex`
- Create: `sidecar/config/config.exs`
- Create: `sidecar/config/runtime.exs`
- Create: `sidecar/config/dev.exs`
- Create: `sidecar/config/test.exs`
- Create: `sidecar/.formatter.exs`
- Create: `sidecar/test/test_helper.exs`

The sidecar depends on the full `claude_code` package — it uses `Adapter.Local` for CLI lifecycle and control protocol, plus `Remote.Protocol` for WebSocket envelope encoding.

**Step 1: Create all scaffold files**

`sidecar/mix.exs`:

```elixir
defmodule ClaudeCode.Sidecar.MixProject do
  use Mix.Project

  def project do
    [
      app: :claude_code_sidecar,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ClaudeCode.Sidecar.Application, []}
    ]
  end

  defp deps do
    [
      # Uses Adapter.Local for CLI lifecycle, Remote.Protocol for envelope encoding
      {:claude_code, path: ".."},
      {:bandit, "~> 1.0"},
      {:websock_adapter, "~> 0.5"},
      # Dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["compile --warnings-as-errors", "format --check-formatted", "credo --strict"]
    ]
  end
end
```

`sidecar/lib/claude_code/sidecar.ex`:

```elixir
defmodule ClaudeCode.Sidecar do
  @moduledoc """
  A WebSocket bridge that runs CC sessions on behalf of remote callers.

  Accepts WebSocket connections, starts a local CC session (via `Adapter.Local`)
  for each connection, and bridges messages between the WebSocket and the CLI subprocess.
  """
end
```

`sidecar/lib/claude_code/sidecar/application.ex`:

```elixir
defmodule ClaudeCode.Sidecar.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:claude_code_sidecar, :port, 4040)

    children = [
      ClaudeCode.Sidecar.SessionRegistry,
      {Bandit,
        plug: ClaudeCode.Sidecar.Router,
        port: port,
        scheme: :http}
    ]

    opts = [strategy: :one_for_one, name: ClaudeCode.Sidecar.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

`sidecar/lib/claude_code/sidecar/router.ex`:

```elixir
defmodule ClaudeCode.Sidecar.Router do
  @moduledoc false
  @behaviour Plug

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["sessions"]} = conn, _opts) do
    auth_token = Application.get_env(:claude_code_sidecar, :auth_token)
    workspaces_root = Application.get_env(:claude_code_sidecar, :workspaces_root, "/workspaces")
    max_sessions = Application.get_env(:claude_code_sidecar, :max_concurrent_sessions, 20)
    idle_timeout = Application.get_env(:claude_code_sidecar, :session_idle_timeout_ms, 600_000)

    # Enforce connection limit
    active = ClaudeCode.Sidecar.SessionRegistry.count()

    if active >= max_sessions do
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(503, "Max concurrent sessions reached (#{max_sessions})")
    else
      case Plug.Conn.get_req_header(conn, "authorization") do
        ["Bearer " <> ^auth_token] ->
          WebSockAdapter.upgrade(
            conn,
            ClaudeCode.Sidecar.SessionHandler,
            [workspaces_root: workspaces_root, idle_timeout_ms: idle_timeout],
            []
          )

        _ ->
          conn
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.send_resp(401, "Unauthorized")
      end
    end
  end

  def call(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(404, "Not Found")
  end
end
```

`sidecar/lib/claude_code/sidecar/session_registry.ex`:

```elixir
defmodule ClaudeCode.Sidecar.SessionRegistry do
  @moduledoc """
  Tracks active WebSocket sessions for connection limiting.

  Uses an Agent wrapping a simple counter. SessionHandler calls
  `register/0` on init and `unregister/0` on terminate.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  @spec register() :: :ok
  def register do
    Agent.update(__MODULE__, &(&1 + 1))
  end

  @spec unregister() :: :ok
  def unregister do
    Agent.update(__MODULE__, &max(&1 - 1, 0))
  end

  @spec count() :: non_neg_integer()
  def count do
    Agent.get(__MODULE__, & &1)
  end
end
```

`sidecar/config/config.exs`:

```elixir
import Config

config :claude_code_sidecar,
  port: 4040,
  workspaces_root: "/workspaces",
  max_concurrent_sessions: 20,
  session_idle_timeout_ms: 600_000

import_config "#{config_env()}.exs"
```

`sidecar/config/runtime.exs`:

```elixir
import Config

if config_env() == :prod do
  config :claude_code_sidecar,
    auth_token: System.fetch_env!("SIDECAR_AUTH_TOKEN"),
    port: String.to_integer(System.get_env("PORT", "4040")),
    workspaces_root: System.get_env("WORKSPACES_ROOT", "/workspaces"),
    max_concurrent_sessions: String.to_integer(System.get_env("MAX_CONCURRENT_SESSIONS", "20")),
    session_idle_timeout_ms: String.to_integer(System.get_env("SESSION_IDLE_TIMEOUT_MS", "600000"))
end
```

`sidecar/config/dev.exs`:

```elixir
import Config

config :claude_code_sidecar,
  auth_token: "dev-token",
  workspaces_root: Path.expand("../tmp/workspaces", __DIR__)
```

`sidecar/config/test.exs`:

```elixir
import Config

config :claude_code_sidecar,
  auth_token: "test-token",
  workspaces_root: Path.expand("../tmp/test_workspaces", __DIR__)

config :logger, level: :warning
```

`sidecar/.formatter.exs`:

```elixir
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

`sidecar/test/test_helper.exs`:

```elixir
ExUnit.start()
```

**Step 2: Verify compilation**

Run: `cd sidecar && mix deps.get && mix compile`
Expected: Clean compile. `SessionHandler` module doesn't exist yet — Router references it but that's a runtime error, not a compile error since it's passed as an atom to `WebSockAdapter.upgrade`.

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

**Step 1: Write the failing tests**

```elixir
# sidecar/test/claude_code/sidecar/workspace_manager_test.exs
defmodule ClaudeCode.Sidecar.WorkspaceManagerTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Sidecar.WorkspaceManager

  setup do
    # Use a temp directory for each test
    root = Path.join(System.tmp_dir!(), "ws_mgr_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  describe "ensure_workspace/2" do
    test "creates workspace directory", %{root: root} do
      assert {:ok, path} = WorkspaceManager.ensure_workspace(root, "agent_abc123")
      assert File.dir?(path)
      assert path == Path.join(root, "agent_abc123")
    end

    test "is idempotent — calling twice returns same path", %{root: root} do
      assert {:ok, path1} = WorkspaceManager.ensure_workspace(root, "agent_abc123")
      assert {:ok, path2} = WorkspaceManager.ensure_workspace(root, "agent_abc123")
      assert path1 == path2
      assert File.dir?(path1)
    end

    test "rejects path traversal with ../", %{root: root} do
      assert {:error, :invalid_workspace_id} = WorkspaceManager.ensure_workspace(root, "../escape")
    end

    test "rejects absolute path", %{root: root} do
      assert {:error, :invalid_workspace_id} = WorkspaceManager.ensure_workspace(root, "/etc/passwd")
    end

    test "rejects empty string", %{root: root} do
      assert {:error, :invalid_workspace_id} = WorkspaceManager.ensure_workspace(root, "")
    end

    test "rejects workspace_id containing /", %{root: root} do
      assert {:error, :invalid_workspace_id} = WorkspaceManager.ensure_workspace(root, "foo/bar")
    end

    test "allows alphanumeric, hyphens, underscores", %{root: root} do
      assert {:ok, _} = WorkspaceManager.ensure_workspace(root, "agent-abc_123")
      assert {:ok, _} = WorkspaceManager.ensure_workspace(root, "ws_ABCD1234")
    end
  end
end
```

**Step 2: Run tests to verify failure**

Run: `cd sidecar && mix test test/claude_code/sidecar/workspace_manager_test.exs`
Expected: Compilation error — module not found

**Step 3: Write implementation**

```elixir
# sidecar/lib/claude_code/sidecar/workspace_manager.ex
defmodule ClaudeCode.Sidecar.WorkspaceManager do
  @moduledoc """
  Manages workspace directories for sidecar sessions.

  Each agent gets a workspace directory under the configured root.
  Workspaces persist across sessions so agents can resume work.
  """

  @valid_id_pattern ~r/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/

  @spec ensure_workspace(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_workspace_id}
  def ensure_workspace(root, workspace_id) do
    if valid_workspace_id?(workspace_id) do
      path = Path.join(root, workspace_id)
      File.mkdir_p!(path)
      {:ok, path}
    else
      {:error, :invalid_workspace_id}
    end
  end

  defp valid_workspace_id?(id) when is_binary(id) and byte_size(id) > 0 do
    Regex.match?(@valid_id_pattern, id) and not String.contains?(id, "..")
  end

  defp valid_workspace_id?(_), do: false
end
```

**Step 4: Run tests**

Run: `cd sidecar && mix test test/claude_code/sidecar/workspace_manager_test.exs`
Expected: All pass

**Step 5: Commit**

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
2. Receives `query` → calls `Adapter.Local.send_query/4`, resets idle timer
3. Receives `{:adapter_raw_message, request_id, decoded_map}` from `Adapter.Local` → re-encodes to JSON, forwards as `message` envelope
4. Detects `decoded_map["type"] == "result"` → sends `done` envelope
5. Receives `{:adapter_error, request_id, reason}` → sends `error` envelope
6. WebSocket disconnect → calls `Adapter.Local.stop/1`, unregisters from SessionRegistry
7. Idle timeout → stops session if no query activity within configured window

**Step 1: Write tests**

Test the bridge behavior: send init, verify ready; send query, verify CC messages forwarded. Use a mock CLI script (shell script that emits canned NDJSON) set via `:cli_path` option so `Adapter.Local` runs the mock instead of the real CLI.

**Step 2: Implement SessionHandler**

Key implementation — the Adapter.Local notification handlers:

```elixir
@impl WebSock
def init(opts) do
  ClaudeCode.Sidecar.SessionRegistry.register()
  idle_timeout_ms = opts[:idle_timeout_ms] || 600_000
  idle_timer = Process.send_after(self(), :idle_timeout, idle_timeout_ms)

  {:ok, %{
    adapter_pid: nil,
    request_id: nil,
    workspace_id: nil,
    workspaces_root: opts[:workspaces_root] || "/workspaces",
    idle_timeout_ms: idle_timeout_ms,
    idle_timer: idle_timer
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
  # Reset idle timer on each query
  if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
  idle_timer = Process.send_after(self(), :idle_timeout, state.idle_timeout_ms)

  request_id = make_ref()
  :ok = ClaudeCode.Adapter.Local.send_query(
    state.adapter_pid, request_id, msg.prompt, Enum.to_list(msg.opts || %{})
  )
  {:ok, %{state | request_id: request_id, wire_request_id: msg.request_id, idle_timer: idle_timer}}
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

def handle_info(:idle_timeout, state) do
  Logger.info("Session idle timeout reached, closing connection")
  {:stop, :normal, state}
end

@impl WebSock
def terminate(_reason, state) do
  ClaudeCode.Sidecar.SessionRegistry.unregister()

  if state.adapter_pid && Process.alive?(state.adapter_pid) do
    ClaudeCode.Adapter.Local.stop(state.adapter_pid)
  end

  :ok
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
- Create: `test/support/mock_cli.sh`
- Create: `test/claude_code/remote/end_to_end_test.exs`

A test that starts the real sidecar (Bandit + SessionHandler) in the test process, connects `Adapter.Remote` to it, and verifies the full flow through `ClaudeCode.Session`. Uses a mock CLI script on the sidecar side (via `:cli_path` option to `Adapter.Local`) that emits canned NDJSON.

This validates the complete path:
```
Session → Adapter.Remote → WebSocket → Sidecar.SessionHandler → Adapter.Local → Port (mock CLI)
  → decoded map → re-encoded JSON → WebSocket → Adapter.Remote → notify_raw_message → Session parses → subscriber
```

**Step 1: Write mock CLI script**

This shell script mimics the CC CLI's stream-json mode. It reads stdin line by line, responds to the initialize handshake, then emits canned assistant + result messages for any query.

```bash
#!/bin/bash
# test/support/mock_cli.sh
# Mock CC CLI for integration testing. Reads stream-json from stdin, writes NDJSON to stdout.

# Read stdin line by line
while IFS= read -r line; do
  # Parse the type field from JSON (crude but sufficient for tests)
  type=$(echo "$line" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

  case "$type" in
    "initialize")
      # Respond with initialize result
      echo '{"type":"initialize","result":{"supported_protocols":["stream-json"],"server_info":{"name":"mock-cli","version":"0.0.1"}}}'
      ;;
    "user_message")
      # Extract session_id if present, default to mock-session
      session_id="mock-session-$(date +%s)"

      # Emit system init
      echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"${session_id}\",\"tools\":[\"Bash\",\"Read\"],\"model\":\"claude-sonnet-4-20250514\",\"permission_mode\":\"default\"}"

      # Emit assistant message
      echo "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_mock\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello from mock CLI!\"}],\"model\":\"claude-sonnet-4-20250514\",\"stop_reason\":\"end_turn\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0,\"server_tool_use_input_tokens\":0}},\"session_id\":\"${session_id}\"}"

      # Emit result
      echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"duration_ms\":100.0,\"duration_api_ms\":80.0,\"num_turns\":1,\"result\":\"Hello from mock CLI!\",\"session_id\":\"${session_id}\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0,\"server_tool_use_input_tokens\":0}}"
      ;;
  esac
done
```

Make it executable: `chmod +x test/support/mock_cli.sh`

**Step 2: Write the end-to-end test**

```elixir
# test/claude_code/remote/end_to_end_test.exs
defmodule ClaudeCode.Remote.EndToEndTest do
  use ExUnit.Case
  @moduletag :integration

  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Session

  setup do
    # Start a real sidecar (Bandit + SessionHandler) on a random port
    workspaces_root = Path.join(System.tmp_dir!(), "e2e_ws_#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspaces_root)

    mock_cli_path = Path.expand("../../support/mock_cli.sh", __DIR__)

    {:ok, pid} =
      Bandit.start_link(
        plug: {ClaudeCode.Sidecar.Router.TestPlug,
          auth_token: "e2e-token",
          workspaces_root: workspaces_root,
          cli_path: mock_cli_path},
        port: 0, ip: :loopback, scheme: :http
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)

    on_exit(fn ->
      Bandit.stop(pid)
      File.rm_rf!(workspaces_root)
    end)

    %{port: port}
  end

  test "full path: Session → Remote → Sidecar → Adapter.Local → mock CLI → back", %{port: port} do
    # Start a Session with the Remote adapter
    {:ok, session} =
      Session.start_link(
        adapter: {ClaudeCode.Adapter.Remote,
          url: "ws://localhost:#{port}/sessions",
          auth_token: "e2e-token",
          workspace_id: "e2e-test-agent"
        }
      )

    # Query through Session — messages flow through the entire stack
    messages =
      session
      |> ClaudeCode.stream("Say hello")
      |> Enum.to_list()

    # Should have at least an assistant message and a result
    assert Enum.any?(messages, &match?(%AssistantMessage{}, &1))

    result = List.last(messages)
    assert %ResultMessage{} = result
    assert result.result == "Hello from mock CLI!"
    refute result.is_error

    ClaudeCode.stop(session)
  end

  test "stream utilities work with remote adapter", %{port: port} do
    {:ok, session} =
      Session.start_link(
        adapter: {ClaudeCode.Adapter.Remote,
          url: "ws://localhost:#{port}/sessions",
          auth_token: "e2e-token",
          workspace_id: "e2e-test-stream"
        }
      )

    final_text =
      session
      |> ClaudeCode.stream("Say hello")
      |> ClaudeCode.Stream.final_text()

    assert final_text == "Hello from mock CLI!"

    ClaudeCode.stop(session)
  end
end
```

Note: `ClaudeCode.Sidecar.Router.TestPlug` is a test-only Plug that accepts `cli_path` in opts and passes it to SessionHandler, so `Adapter.Local` uses the mock CLI instead of the real one. If the Router doesn't support this, you may need to configure the sidecar's `Adapter.Local` opts via application config or add a test-specific router.

**Step 3: Run the test**

Run: `mix test test/claude_code/remote/end_to_end_test.exs --include integration`
Expected: All pass

**Step 4: Commit**

```
git add test/support/mock_cli.sh test/claude_code/remote/end_to_end_test.exs
git commit -m "test: add end-to-end integration test for remote adapter stack"
```

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

12. **Session option serialization** — Elixir-native session options must be converted to JSON-serializable format before sending over the wire. The adapter's `serialize_query_opts/1` and `serialize_value/1` handle this: atoms become strings (`:sonnet` → `"sonnet"`), keyword lists become maps, nested structures are recursed. The sidecar's `build_adapter_opts/3` reverses this conversion when constructing `Adapter.Local` options. Keys like `:model`, `:system_prompt`, `:max_turns` survive the round-trip; function-valued keys are stripped by `filter_non_serializable_opts/1`.

13. **Heartbeat keepalive** — The adapter sends a WebSocket ping every 30s via `Process.send_after` loop, starting once the connection reaches `:ready` state. Expects pong within 10s. Two consecutive missed pongs trigger disconnect. This prevents silent WebSocket drops through proxies and load balancers during long-running tool executions where no CC messages flow for minutes. The sidecar responds to pings automatically (standard WebSocket behavior).

14. **Connection limits** — `SessionRegistry` (Agent-based counter) tracks active WebSocket sessions. The Router checks the count before upgrading connections and returns HTTP 503 when `max_concurrent_sessions` is reached. Default: 20.

15. **Idle timeout** — SessionHandler starts a timer on init and resets it on each `query` message (not on heartbeat pings). When the timer fires with no query activity, the handler closes the WebSocket connection, which triggers `terminate/2` to unregister from SessionRegistry and stop `Adapter.Local`. Default: 10 minutes.

16. **`can_use_tool` protocol slot** — The `control` envelope type with `subtype: "can_use_tool"` is reserved in the protocol for future WebSocket-based forwarding of CC permission checks. Not implemented in v1 — the protocol slot exists so a future version can add it without a protocol version bump. See design doc "Remote Adapter Limitations" section.
