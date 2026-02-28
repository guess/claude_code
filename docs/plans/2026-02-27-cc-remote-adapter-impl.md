# Remote Adapter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a WebSocket-based remote adapter to `claude_code` and a standalone sidecar application in the same repo, enabling CC sessions to run on a remote server.

**Architecture:** Two new modules in `claude_code` (`ClaudeCode.Remote.Protocol` for shared wire format, `ClaudeCode.Adapter.Remote` for the WebSocket client adapter). A separate `sidecar/` mix project (`claude_code_sidecar`) for the WebSocket server that bridges connections to local CC sessions.

**Tech Stack:** `mint_web_socket` (adapter WS client), `bandit` + `websock` (sidecar WS server), built-in `JSON` module (Elixir 1.18+), existing `ClaudeCode.Adapter` behaviour.

**Design doc:** `docs/plans/2026-02-27-cc-remote-adapter.md`

---

## Phase 1: Shared Protocol

### Task 1: Protocol — Host-to-Sidecar Message Encoding

**Files:**
- Create: `lib/claude_code/remote/protocol.ex`
- Create: `test/claude_code/remote/protocol_test.exs`

**Step 1: Write the failing tests**

```elixir
# test/claude_code/remote/protocol_test.exs
defmodule ClaudeCode.Remote.ProtocolTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Remote.Protocol

  describe "encode_init/1" do
    test "encodes init message with protocol version" do
      opts = %{
        session_opts: %{model: "sonnet", system_prompt: "You are helpful."},
        workspace_id: "agent_abc123"
      }

      {:ok, json} = Protocol.encode_init(opts)
      decoded = JSON.decode!(json)

      assert decoded["type"] == "init"
      assert decoded["protocol_version"] == 1
      assert decoded["workspace_id"] == "agent_abc123"
      assert decoded["session_opts"]["model"] == "sonnet"
      assert decoded["session_opts"]["system_prompt"] == "You are helpful."
      refute Map.has_key?(decoded, "resume")
    end

    test "encodes init message with resume session_id" do
      opts = %{
        session_opts: %{model: "sonnet"},
        workspace_id: "agent_abc123",
        resume: "session-uuid-123"
      }

      {:ok, json} = Protocol.encode_init(opts)
      decoded = JSON.decode!(json)

      assert decoded["resume"] == "session-uuid-123"
    end
  end

  describe "encode_query/1" do
    test "encodes query message" do
      msg = %{request_id: "req-1", prompt: "Hello", opts: %{max_turns: 5}}

      {:ok, json} = Protocol.encode_query(msg)
      decoded = JSON.decode!(json)

      assert decoded["type"] == "query"
      assert decoded["request_id"] == "req-1"
      assert decoded["prompt"] == "Hello"
      assert decoded["opts"]["max_turns"] == 5
    end
  end

  describe "encode_stop/0" do
    test "encodes stop message" do
      {:ok, json} = Protocol.encode_stop()
      assert JSON.decode!(json) == %{"type" => "stop"}
    end
  end

  describe "encode_interrupt/0" do
    test "encodes interrupt message" do
      {:ok, json} = Protocol.encode_interrupt()
      assert JSON.decode!(json) == %{"type" => "interrupt"}
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/remote/protocol_test.exs`
Expected: Compilation error — `ClaudeCode.Remote.Protocol` not found

**Step 3: Write minimal implementation**

```elixir
# lib/claude_code/remote/protocol.ex
defmodule ClaudeCode.Remote.Protocol do
  @moduledoc """
  Shared message encoding/decoding for the ClaudeCode remote WebSocket protocol.

  All messages are JSON objects with a `type` field. This module handles
  both host→sidecar and sidecar→host message formats.

  ## Protocol Version

  The `init` message includes `protocol_version: 1`. Both sides should
  validate compatibility before proceeding.
  """

  @protocol_version 1

  @doc "Returns the current protocol version."
  @spec protocol_version() :: pos_integer()
  def protocol_version, do: @protocol_version

  # ============================================================================
  # Host → Sidecar Encoding
  # ============================================================================

  @doc """
  Encodes an `init` message sent when a new connection is established.

  ## Options

    * `:session_opts` (required) — Map of CC session options (model, system_prompt, etc.)
    * `:workspace_id` (required) — Workspace directory identifier
    * `:resume` (optional) — Session ID to resume a previous conversation

  """
  @spec encode_init(map()) :: {:ok, String.t()}
  def encode_init(%{session_opts: session_opts, workspace_id: workspace_id} = opts) do
    message = %{
      type: "init",
      protocol_version: @protocol_version,
      workspace_id: workspace_id,
      session_opts: session_opts
    }

    message =
      case Map.get(opts, :resume) do
        nil -> message
        session_id -> Map.put(message, :resume, session_id)
      end

    {:ok, JSON.encode!(message)}
  end

  @doc "Encodes a `query` message to start a new query."
  @spec encode_query(map()) :: {:ok, String.t()}
  def encode_query(%{request_id: request_id, prompt: prompt} = msg) do
    {:ok,
     JSON.encode!(%{
       type: "query",
       request_id: request_id,
       prompt: prompt,
       opts: Map.get(msg, :opts, %{})
     })}
  end

  @doc "Encodes a `stop` message to end the session."
  @spec encode_stop() :: {:ok, String.t()}
  def encode_stop, do: {:ok, JSON.encode!(%{type: "stop"})}

  @doc "Encodes an `interrupt` message to cancel the current query."
  @spec encode_interrupt() :: {:ok, String.t()}
  def encode_interrupt, do: {:ok, JSON.encode!(%{type: "interrupt"})}
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/remote/protocol_test.exs`
Expected: All pass

**Step 5: Commit**

```
git add lib/claude_code/remote/protocol.ex test/claude_code/remote/protocol_test.exs
git commit -m "feat: add Remote.Protocol with host-to-sidecar message encoding"
```

---

### Task 2: Protocol — Sidecar-to-Host Message Encoding & Decoding

**Files:**
- Modify: `lib/claude_code/remote/protocol.ex`
- Modify: `test/claude_code/remote/protocol_test.exs`

**Step 1: Write the failing tests**

Add to `protocol_test.exs`:

```elixir
  # Sidecar → Host encoding

  describe "encode_ready/1" do
    test "encodes ready ack with session_id" do
      {:ok, json} = Protocol.encode_ready("session-uuid-456")
      decoded = JSON.decode!(json)

      assert decoded["type"] == "ready"
      assert decoded["session_id"] == "session-uuid-456"
    end
  end

  describe "encode_message/2" do
    test "encodes a CC message envelope" do
      {:ok, json} = Protocol.encode_message("req-1", %{"type" => "assistant", "message" => %{}})
      decoded = JSON.decode!(json)

      assert decoded["type"] == "message"
      assert decoded["request_id"] == "req-1"
      assert decoded["payload"]["type"] == "assistant"
    end
  end

  describe "encode_done/2" do
    test "encodes done with reason" do
      {:ok, json} = Protocol.encode_done("req-1", "completed")
      decoded = JSON.decode!(json)

      assert decoded["type"] == "done"
      assert decoded["request_id"] == "req-1"
      assert decoded["reason"] == "completed"
    end
  end

  describe "encode_error/3" do
    test "encodes error with code and details" do
      {:ok, json} = Protocol.encode_error("req-1", "session_failed", "CLI exited with code 1")
      decoded = JSON.decode!(json)

      assert decoded["type"] == "error"
      assert decoded["request_id"] == "req-1"
      assert decoded["code"] == "session_failed"
      assert decoded["details"] == "CLI exited with code 1"
    end
  end

  # Decoding (both directions)

  describe "decode/1" do
    test "decodes init message" do
      json = ~s({"type":"init","protocol_version":1,"workspace_id":"ws1","session_opts":{"model":"sonnet"}})
      assert {:ok, %{type: :init, protocol_version: 1, workspace_id: "ws1", session_opts: %{"model" => "sonnet"}}} = Protocol.decode(json)
    end

    test "decodes ready message" do
      json = ~s({"type":"ready","session_id":"sess-123"})
      assert {:ok, %{type: :ready, session_id: "sess-123"}} = Protocol.decode(json)
    end

    test "decodes message envelope" do
      json = ~s({"type":"message","request_id":"req-1","payload":{"type":"assistant"}})
      assert {:ok, %{type: :message, request_id: "req-1", payload: %{"type" => "assistant"}}} = Protocol.decode(json)
    end

    test "decodes done message" do
      json = ~s({"type":"done","request_id":"req-1","reason":"completed"})
      assert {:ok, %{type: :done, request_id: "req-1", reason: "completed"}} = Protocol.decode(json)
    end

    test "decodes error message" do
      json = ~s({"type":"error","request_id":"req-1","code":"timeout","details":"took too long"})
      assert {:ok, %{type: :error, request_id: "req-1", code: "timeout", details: "took too long"}} = Protocol.decode(json)
    end

    test "decodes query message" do
      json = ~s({"type":"query","request_id":"req-1","prompt":"hello","opts":{}})
      assert {:ok, %{type: :query, request_id: "req-1", prompt: "hello"}} = Protocol.decode(json)
    end

    test "decodes stop message" do
      json = ~s({"type":"stop"})
      assert {:ok, %{type: :stop}} = Protocol.decode(json)
    end

    test "decodes interrupt message" do
      json = ~s({"type":"interrupt"})
      assert {:ok, %{type: :interrupt}} = Protocol.decode(json)
    end

    test "returns error for unknown type" do
      json = ~s({"type":"unknown_thing"})
      assert {:error, {:unknown_message_type, "unknown_thing"}} = Protocol.decode(json)
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Protocol.decode("not json")
    end
  end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/remote/protocol_test.exs`
Expected: FAIL — missing functions

**Step 3: Write implementation**

Add to `protocol.ex`:

```elixir
  # ============================================================================
  # Sidecar → Host Encoding
  # ============================================================================

  @doc "Encodes a `ready` ack with the CC session ID."
  @spec encode_ready(String.t()) :: {:ok, String.t()}
  def encode_ready(session_id) do
    {:ok, JSON.encode!(%{type: "ready", session_id: session_id})}
  end

  @doc "Encodes a `message` envelope wrapping a CC message."
  @spec encode_message(String.t(), map()) :: {:ok, String.t()}
  def encode_message(request_id, payload) do
    {:ok, JSON.encode!(%{type: "message", request_id: request_id, payload: payload})}
  end

  @doc "Encodes a `done` message signaling query completion."
  @spec encode_done(String.t(), String.t()) :: {:ok, String.t()}
  def encode_done(request_id, reason) do
    {:ok, JSON.encode!(%{type: "done", request_id: request_id, reason: reason})}
  end

  @doc "Encodes an `error` message."
  @spec encode_error(String.t(), String.t(), String.t()) :: {:ok, String.t()}
  def encode_error(request_id, code, details) do
    {:ok, JSON.encode!(%{type: "error", request_id: request_id, code: code, details: details})}
  end

  # ============================================================================
  # Decoding (both directions)
  # ============================================================================

  @doc """
  Decodes a JSON string into a protocol message map with atom type keys.

  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(json) do
    case JSON.decode(json) do
      {:ok, %{"type" => type} = raw} -> decode_typed(type, raw)
      {:ok, _other} -> {:error, :missing_type_field}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp decode_typed("init", raw) do
    {:ok,
     %{
       type: :init,
       protocol_version: raw["protocol_version"],
       workspace_id: raw["workspace_id"],
       session_opts: raw["session_opts"],
       resume: raw["resume"]
     }}
  end

  defp decode_typed("ready", raw) do
    {:ok, %{type: :ready, session_id: raw["session_id"]}}
  end

  defp decode_typed("message", raw) do
    {:ok, %{type: :message, request_id: raw["request_id"], payload: raw["payload"]}}
  end

  defp decode_typed("done", raw) do
    {:ok, %{type: :done, request_id: raw["request_id"], reason: raw["reason"]}}
  end

  defp decode_typed("error", raw) do
    {:ok,
     %{
       type: :error,
       request_id: raw["request_id"],
       code: raw["code"],
       details: raw["details"]
     }}
  end

  defp decode_typed("query", raw) do
    {:ok,
     %{
       type: :query,
       request_id: raw["request_id"],
       prompt: raw["prompt"],
       opts: raw["opts"]
     }}
  end

  defp decode_typed("control", raw) do
    {:ok,
     %{
       type: :control,
       request_id: raw["request_id"],
       subtype: raw["subtype"],
       params: raw["params"]
     }}
  end

  defp decode_typed("control_response", raw) do
    {:ok,
     %{
       type: :control_response,
       request_id: raw["request_id"],
       response: raw["response"]
     }}
  end

  defp decode_typed("stop", _raw), do: {:ok, %{type: :stop}}
  defp decode_typed("interrupt", _raw), do: {:ok, %{type: :interrupt}}
  defp decode_typed(unknown, _raw), do: {:error, {:unknown_message_type, unknown}}
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/remote/protocol_test.exs`
Expected: All pass

**Step 5: Commit**

```
git add lib/claude_code/remote/protocol.ex test/claude_code/remote/protocol_test.exs
git commit -m "feat: add sidecar-to-host encoding and bidirectional decoding to Protocol"
```

---

## Phase 2: Remote Adapter

### Task 3: Add `mint_web_socket` Dependency

**Files:**
- Modify: `mix.exs`

**Step 1: Add the dependency**

Add to `deps()` in `mix.exs`, in the production dependencies section:

```elixir
{:mint_web_socket, "~> 1.0"},
```

**Step 2: Fetch deps**

Run: `mix deps.get`
Expected: Successfully fetched `mint_web_socket` and its deps (`mint`, `mint_web_socket`)

**Step 3: Verify compilation**

Run: `mix compile`
Expected: Clean compile

**Step 4: Commit**

```
git add mix.exs mix.lock
git commit -m "deps: add mint_web_socket for remote adapter WebSocket client"
```

---

### Task 4: Remote Adapter — GenServer Skeleton

**Files:**
- Create: `lib/claude_code/adapter/remote.ex`
- Create: `test/claude_code/adapter/remote_test.exs`

**Step 1: Write the failing tests**

```elixir
# test/claude_code/adapter/remote_test.exs
defmodule ClaudeCode.Adapter.RemoteTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Adapter.Remote

  describe "config validation" do
    test "validates required url" do
      assert {:error, _} = Remote.validate_config(auth_token: "tok")
    end

    test "validates required auth_token" do
      assert {:error, _} = Remote.validate_config(url: "wss://example.com/sessions")
    end

    test "accepts valid config with defaults" do
      assert {:ok, config} =
               Remote.validate_config(
                 url: "wss://example.com/sessions",
                 auth_token: "tok"
               )

      assert config[:url] == "wss://example.com/sessions"
      assert config[:auth_token] == "tok"
      assert config[:connect_timeout] == 10_000
      assert config[:init_timeout] == 30_000
      assert is_binary(config[:workspace_id])
    end

    test "accepts explicit workspace_id" do
      assert {:ok, config} =
               Remote.validate_config(
                 url: "wss://example.com/sessions",
                 auth_token: "tok",
                 workspace_id: "my-workspace"
               )

      assert config[:workspace_id] == "my-workspace"
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/adapter/remote_test.exs`
Expected: Compilation error — module not found

**Step 3: Write the GenServer skeleton**

```elixir
# lib/claude_code/adapter/remote.ex
defmodule ClaudeCode.Adapter.Remote do
  @moduledoc """
  WebSocket client adapter for remote CC session execution.

  Connects to a `ClaudeCode.Sidecar` instance over WebSocket and bridges
  messages between the Session GenServer and the remote CC session.

  ## Usage

      {:ok, session} = ClaudeCode.start_link(
        adapter: {ClaudeCode.Adapter.Remote,
          url: "wss://agent-runner.example.com/sessions",
          auth_token: "secret-token",
          workspace_id: "agent_abc123"
        },
        model: "sonnet",
        system_prompt: "You are helpful."
      )

  ## Config Options

    * `:url` (required) — WebSocket URL of the sidecar
    * `:auth_token` (required) — Bearer token for authentication
    * `:workspace_id` (optional) — Workspace directory name (auto-generated if omitted)
    * `:connect_timeout` (optional) — WebSocket connect timeout in ms (default: 10_000)
    * `:init_timeout` (optional) — Time to wait for ready ack (default: 30_000)

  """

  use GenServer

  @behaviour ClaudeCode.Adapter

  alias ClaudeCode.Adapter
  alias ClaudeCode.Remote.Protocol

  require Logger

  @config_schema NimbleOptions.new!(
                   url: [type: :string, required: true, doc: "WebSocket URL of the sidecar"],
                   auth_token: [
                     type: :string,
                     required: true,
                     doc: "Bearer token for authentication"
                   ],
                   workspace_id: [
                     type: :string,
                     default: nil,
                     doc: "Workspace directory name"
                   ],
                   connect_timeout: [
                     type: :pos_integer,
                     default: 10_000,
                     doc: "WebSocket connect timeout (ms)"
                   ],
                   init_timeout: [
                     type: :pos_integer,
                     default: 30_000,
                     doc: "Time to wait for ready ack (ms)"
                   ]
                 )

  defstruct [
    :session,
    :session_options,
    :conn,
    :websocket,
    :request_ref,
    :request_id,
    :remote_session_id,
    :config,
    :buffer,
    status: :provisioning
  ]

  # ============================================================================
  # Public API (config validation, for testing)
  # ============================================================================

  @doc "Validates adapter config. Returns `{:ok, validated}` or `{:error, reason}`."
  @spec validate_config(keyword()) :: {:ok, keyword()} | {:error, term()}
  def validate_config(config) do
    case NimbleOptions.validate(config, @config_schema) do
      {:ok, validated} ->
        validated =
          if validated[:workspace_id] do
            validated
          else
            Keyword.put(validated, :workspace_id, generate_workspace_id())
          end

        {:ok, validated}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Adapter Behaviour
  # ============================================================================

  @impl Adapter
  def start_link(session, opts) do
    GenServer.start_link(__MODULE__, {session, opts})
  end

  @impl Adapter
  def send_query(adapter, request_id, prompt, opts) do
    GenServer.call(adapter, {:query, request_id, prompt, opts})
  end

  @impl Adapter
  def health(adapter) do
    GenServer.call(adapter, :health)
  end

  @impl Adapter
  def stop(adapter) do
    GenServer.call(adapter, :stop)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init({session, opts}) do
    Process.link(session)

    {adapter_config, session_options} = extract_adapter_config(opts)

    case validate_config(adapter_config) do
      {:ok, config} ->
        Adapter.notify_status(session, :provisioning)

        state = %__MODULE__{
          session: session,
          session_options: session_options,
          config: config,
          buffer: ""
        }

        {:ok, state, {:continue, :connect}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    # TODO: WebSocket connection (Task 5)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:health, _from, %{status: :provisioning} = state) do
    {:reply, {:unhealthy, :provisioning}, state}
  end

  def handle_call(:health, _from, %{conn: nil} = state) do
    {:reply, {:unhealthy, :disconnected}, state}
  end

  def handle_call(:health, _from, state) do
    {:reply, :healthy, state}
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    if state.conn do
      {:ok, json} = Protocol.encode_stop()
      send_ws_frame(state, {:text, json})
      close_connection(state)
    end

    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_call({:query, _request_id, _prompt, _opts}, _from, %{status: :provisioning} = state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:query, request_id, prompt, opts}, _from, state) do
    # TODO: send query (Task 6)
    {:reply, {:error, :not_implemented}, %{state | request_id: request_id}}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp extract_adapter_config(opts) do
    adapter_keys = [:url, :auth_token, :workspace_id, :connect_timeout, :init_timeout]
    {adapter_config, session_options} = Keyword.split(opts, adapter_keys)
    {adapter_config, session_options}
  end

  defp generate_workspace_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp send_ws_frame(_state, _frame) do
    # TODO: implement with Mint.WebSocket (Task 5)
    :ok
  end

  defp close_connection(_state) do
    # TODO: implement with Mint.HTTP (Task 5)
    :ok
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/remote_test.exs`
Expected: All pass

**Step 5: Commit**

```
git add lib/claude_code/adapter/remote.ex test/claude_code/adapter/remote_test.exs
git commit -m "feat: add Adapter.Remote GenServer skeleton with config validation"
```

---

### Task 5: Remote Adapter — WebSocket Connection

**Files:**
- Modify: `lib/claude_code/adapter/remote.ex`
- Modify: `test/claude_code/adapter/remote_test.exs`

This task implements the WebSocket connection using `mint_web_socket`. Since the real connection requires a running sidecar, we test URL parsing and the connection lifecycle indirectly.

**Step 1: Write the failing tests**

Add to `remote_test.exs`:

```elixir
  describe "parse_url/1" do
    test "parses wss URL" do
      assert {:ok, :https, "example.com", 443, "/sessions"} =
               Remote.parse_url("wss://example.com/sessions")
    end

    test "parses ws URL" do
      assert {:ok, :http, "localhost", 4040, "/sessions"} =
               Remote.parse_url("ws://localhost:4040/sessions")
    end

    test "parses wss URL with explicit port" do
      assert {:ok, :https, "example.com", 8443, "/ws"} =
               Remote.parse_url("wss://example.com:8443/ws")
    end

    test "returns error for invalid URL" do
      assert {:error, _} = Remote.parse_url("not-a-url")
    end
  end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/adapter/remote_test.exs`
Expected: FAIL — `parse_url/1` not found

**Step 3: Implement URL parsing and WebSocket connection**

Add to `remote.ex` (public helper and updated connection logic):

```elixir
  @doc false
  @spec parse_url(String.t()) :: {:ok, :http | :https, String.t(), pos_integer(), String.t()} | {:error, term()}
  def parse_url(url) do
    uri = URI.parse(url)

    case uri.scheme do
      "wss" -> {:ok, :https, uri.host, uri.port || 443, uri.path || "/"}
      "ws" -> {:ok, :http, uri.host, uri.port || 80, uri.path || "/"}
      _ -> {:error, {:invalid_scheme, uri.scheme}}
    end
  rescue
    _ -> {:error, :invalid_url}
  end
```

Update `handle_continue(:connect, state)`:

```elixir
  @impl GenServer
  def handle_continue(:connect, state) do
    case connect_websocket(state) do
      {:ok, state} ->
        # Send init message
        {:ok, json} = Protocol.encode_init(%{
          session_opts: session_opts_for_wire(state.session_options),
          workspace_id: state.config[:workspace_id],
          resume: state.remote_session_id
        })

        state = send_ws_frame(state, {:text, json})

        # Set init timeout
        init_ref = Process.send_after(self(), :init_timeout, state.config[:init_timeout])
        {:noreply, %{state | init_timer: init_ref}}

      {:error, reason} ->
        Logger.error("Remote adapter failed to connect: #{inspect(reason)}")
        Adapter.notify_status(state.session, {:error, {:connect_failed, reason}})
        {:stop, {:connect_failed, reason}, state}
    end
  end

  defp connect_websocket(state) do
    with {:ok, scheme, host, port, path} <- parse_url(state.config[:url]),
         {:ok, conn} <-
           Mint.HTTP.connect(scheme, host, port,
             transport_opts: transport_opts(scheme),
             protocols: [:http1]
           ),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(scheme, conn, path, [
             {"authorization", "Bearer #{state.config[:auth_token]}"}
           ]) do
      {:ok, %{state | conn: conn, request_ref: ref, status: :connecting}}
    end
  end

  defp transport_opts(:https), do: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
  defp transport_opts(:http), do: []

  defp session_opts_for_wire(opts) do
    # Convert session options to a JSON-safe map
    # Strip adapter-specific and Elixir-process-specific keys
    opts
    |> Keyword.drop([:adapter, :name, :api_key, :callers])
    |> Map.new()
  end
```

Add `init_timer` to the struct:

```elixir
  defstruct [
    :session,
    :session_options,
    :conn,
    :websocket,
    :request_ref,
    :request_id,
    :remote_session_id,
    :config,
    :buffer,
    :init_timer,
    status: :provisioning
  ]
```

Update `send_ws_frame/2` and `close_connection/1`:

```elixir
  defp send_ws_frame(%{conn: conn, websocket: ws, request_ref: ref} = state, frame)
       when not is_nil(ws) do
    case Mint.WebSocket.encode(ws, frame) do
      {:ok, ws, data} ->
        case Mint.WebSocket.stream_request_body(conn, ref, data) do
          {:ok, conn} -> %{state | conn: conn, websocket: ws}
          {:error, _conn, reason} ->
            Logger.error("Failed to send WS frame: #{inspect(reason)}")
            state
        end

      {:error, ws, reason} ->
        Logger.error("Failed to encode WS frame: #{inspect(reason)}")
        %{state | websocket: ws}
    end
  end

  defp send_ws_frame(state, _frame), do: state

  defp close_connection(%{conn: conn} = state) when not is_nil(conn) do
    Mint.HTTP.close(conn)
    %{state | conn: nil, websocket: nil}
  end

  defp close_connection(state), do: state
```

Add handler for Mint TCP/SSL messages and init timeout:

```elixir
  @impl GenServer
  def handle_info(:init_timeout, %{status: status} = state) when status != :ready do
    Logger.error("Remote adapter init timeout — sidecar did not send ready ack")
    Adapter.notify_status(state.session, {:error, :init_timeout})
    {:stop, :init_timeout, close_connection(state)}
  end

  def handle_info(:init_timeout, state) do
    # Already ready, ignore stale timer
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn}
        handle_ws_responses(responses, state)

      {:error, conn, reason, _responses} ->
        Logger.error("WebSocket stream error: #{inspect(reason)}")
        handle_disconnect(%{state | conn: conn}, reason)

      :unknown ->
        Logger.warning("Remote adapter received unknown message: #{inspect(message)}")
        {:noreply, state}
    end
  end

  defp handle_ws_responses(responses, state) do
    Enum.reduce_while(responses, {:noreply, state}, fn response, {_, state} ->
      case handle_ws_response(response, state) do
        {:noreply, state} -> {:cont, {:noreply, state}}
        {:stop, reason, state} -> {:halt, {:stop, reason, state}}
      end
    end)
  end

  defp handle_ws_response({:status, _ref, status}, state) do
    {:noreply, %{state | status: if(status == 101, do: :upgrading, else: :error)}}
  end

  defp handle_ws_response({:headers, _ref, headers}, state) do
    case Mint.WebSocket.new(state.conn, state.request_ref, status_code(state), headers) do
      {:ok, conn, websocket} ->
        {:noreply, %{state | conn: conn, websocket: websocket, status: :connected}}

      {:error, conn, reason} ->
        Logger.error("WebSocket upgrade failed: #{inspect(reason)}")
        Adapter.notify_status(state.session, {:error, {:upgrade_failed, reason}})
        {:stop, {:upgrade_failed, reason}, %{state | conn: conn}}
    end
  end

  defp handle_ws_response({:data, _ref, data}, state) do
    case Mint.WebSocket.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        state = %{state | websocket: websocket}
        handle_ws_frames(frames, state)

      {:error, websocket, reason} ->
        Logger.error("WebSocket decode error: #{inspect(reason)}")
        {:noreply, %{state | websocket: websocket}}
    end
  end

  defp handle_ws_response({:done, _ref}, state) do
    {:noreply, state}
  end

  defp handle_ws_frames(frames, state) do
    Enum.reduce_while(frames, {:noreply, state}, fn frame, {_, state} ->
      case handle_ws_frame(frame, state) do
        {:noreply, state} -> {:cont, {:noreply, state}}
        {:stop, reason, state} -> {:halt, {:stop, reason, state}}
      end
    end)
  end

  defp handle_ws_frame({:text, text}, state) do
    case Protocol.decode(text) do
      {:ok, message} -> handle_protocol_message(message, state)
      {:error, reason} ->
        Logger.warning("Failed to decode protocol message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp handle_ws_frame({:ping, data}, state) do
    state = send_ws_frame(state, {:pong, data})
    {:noreply, state}
  end

  defp handle_ws_frame({:close, _code, _reason}, state) do
    handle_disconnect(state, :ws_closed)
  end

  defp handle_ws_frame(_frame, state) do
    {:noreply, state}
  end

  # Protocol message handlers

  defp handle_protocol_message(%{type: :ready, session_id: session_id}, state) do
    if state.init_timer, do: Process.cancel_timer(state.init_timer)

    Logger.info("Remote adapter ready, session_id: #{session_id}")
    Adapter.notify_status(state.session, :ready)

    {:noreply, %{state | remote_session_id: session_id, status: :ready, init_timer: nil}}
  end

  defp handle_protocol_message(%{type: :message, request_id: _req_id, payload: payload}, state) do
    case ClaudeCode.CLI.Parser.parse_message(payload) do
      {:ok, message} ->
        Adapter.notify_message(state.session, state.request_id, message)

      {:error, reason} ->
        Logger.warning("Failed to parse CC message from sidecar: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp handle_protocol_message(%{type: :done}, state) do
    Adapter.notify_done(state.session, state.request_id, :completed)
    {:noreply, %{state | request_id: nil}}
  end

  defp handle_protocol_message(%{type: :error, code: code, details: details}, state) do
    Adapter.notify_error(state.session, state.request_id, {code, details})
    {:noreply, %{state | request_id: nil}}
  end

  defp handle_protocol_message(_msg, state) do
    {:noreply, state}
  end

  defp handle_disconnect(state, reason) do
    if state.request_id do
      Adapter.notify_error(state.session, state.request_id, {:disconnected, reason})
    end

    {:stop, {:disconnected, reason}, close_connection(state)}
  end

  defp status_code(%{status: :upgrading}), do: 101
  defp status_code(_), do: nil
```

Note: The `status_code` helper and the `handle_ws_response` for `:status` need to store the status code. Add `http_status: nil` to the struct and update accordingly:

```elixir
  defstruct [
    :session,
    :session_options,
    :conn,
    :websocket,
    :request_ref,
    :request_id,
    :remote_session_id,
    :config,
    :buffer,
    :init_timer,
    :http_status,
    status: :provisioning
  ]

  # Update handle_ws_response for :status
  defp handle_ws_response({:status, _ref, status}, state) do
    {:noreply, %{state | http_status: status}}
  end

  # Update handle_ws_response for :headers to use stored http_status
  defp handle_ws_response({:headers, _ref, headers}, state) do
    case Mint.WebSocket.new(state.conn, state.request_ref, state.http_status, headers) do
      # ... same as above
    end
  end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/remote_test.exs`
Expected: All pass (we're testing parse_url and config validation; connection tests need a real server)

**Step 5: Commit**

```
git add lib/claude_code/adapter/remote.ex test/claude_code/adapter/remote_test.exs
git commit -m "feat: add WebSocket connection, init handshake, and message handling to Adapter.Remote"
```

---

### Task 6: Remote Adapter — Query Sending

**Files:**
- Modify: `lib/claude_code/adapter/remote.ex`

**Step 1: Update the query handler**

Replace the TODO `handle_call({:query, ...})` clause:

```elixir
  def handle_call({:query, request_id, prompt, opts}, _from, state) do
    serialized_id = inspect(request_id)

    {:ok, json} =
      Protocol.encode_query(%{
        request_id: serialized_id,
        prompt: prompt,
        opts: Map.new(opts)
      })

    state = %{state | request_id: request_id}
    state = send_ws_frame(state, {:text, json})
    {:reply, :ok, state}
  end
```

Note: `request_id` is a reference internally but needs to be a string on the wire. The adapter maps between them. The sidecar echoes back the string `request_id`, and the adapter uses its stored `state.request_id` reference for Session notifications.

**Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean compile

**Step 3: Commit**

```
git add lib/claude_code/adapter/remote.ex
git commit -m "feat: implement send_query in Adapter.Remote"
```

---

### Task 7: Remote Adapter — Integration Test with Mock Server

**Files:**
- Create: `test/claude_code/adapter/remote_integration_test.exs`
- Create: `test/support/mock_sidecar.ex`

This test starts a real WebSocket server in the test, connects the adapter to it, and verifies end-to-end message flow.

**Step 1: Write the mock sidecar**

```elixir
# test/support/mock_sidecar.ex
defmodule ClaudeCode.Test.MockSidecar do
  @moduledoc false
  # Minimal WebSocket server for testing Adapter.Remote.
  # Starts Bandit on a random port, accepts one connection,
  # and plays back canned CC messages.

  @behaviour WebSock

  def start(opts \\ []) do
    messages = Keyword.get(opts, :messages, [])
    test_pid = self()

    {:ok, _} =
      Bandit.start_link(
        plug: {__MODULE__.Plug, test_pid: test_pid, messages: messages},
        port: 0,
        ip: :loopback,
        scheme: :http
      )
      |> case do
        {:ok, pid} ->
          {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
          {:ok, %{pid: pid, port: port}}
      end
  end

  defmodule Plug do
    @moduledoc false
    @behaviour Plug

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, opts) do
      WebSockAdapter.upgrade(conn, ClaudeCode.Test.MockSidecar, opts, [])
    end
  end

  # WebSock callbacks

  @impl WebSock
  def init(opts) do
    {:ok, %{test_pid: opts[:test_pid], messages: opts[:messages], ready: false}}
  end

  @impl WebSock
  def handle_in({text, [opcode: :text]}, state) do
    case JSON.decode!(text) do
      %{"type" => "init"} ->
        send(state.test_pid, {:sidecar_received, :init, JSON.decode!(text)})
        {:ok, ready_json} = ClaudeCode.Remote.Protocol.encode_ready("test-session-123")
        {:push, {:text, ready_json}, %{state | ready: true}}

      %{"type" => "query", "request_id" => req_id} ->
        send(state.test_pid, {:sidecar_received, :query, req_id})
        # Send canned messages then done
        frames =
          Enum.map(state.messages, fn msg ->
            {:ok, json} = ClaudeCode.Remote.Protocol.encode_message(req_id, msg)
            {:text, json}
          end)

        {:ok, done_json} = ClaudeCode.Remote.Protocol.encode_done(req_id, "completed")
        frames = frames ++ [{:text, done_json}]
        {:push, frames, state}

      %{"type" => "stop"} ->
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
  # Not async — uses shared Bandit server
  use ExUnit.Case

  alias ClaudeCode.Adapter.Remote
  alias ClaudeCode.Test.MockSidecar

  @moduletag :integration

  setup do
    # Canned CC messages the mock sidecar will return
    assistant_msg = %{
      "type" => "assistant",
      "message" => %{
        "id" => "msg_001",
        "type" => "message",
        "role" => "assistant",
        "content" => [%{"type" => "text", "text" => "Hello from remote!"}],
        "model" => "claude-sonnet-4-20250514",
        "stop_reason" => "end_turn",
        "stop_sequence" => nil,
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 5,
          "cache_creation_input_tokens" => 0,
          "cache_read_input_tokens" => 0,
          "server_tool_use_input_tokens" => 0
        }
      },
      "session_id" => "test-session-123"
    }

    result_msg = %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "duration_ms" => 1234.0,
      "duration_api_ms" => 1000.0,
      "num_turns" => 1,
      "result" => "Hello from remote!",
      "session_id" => "test-session-123",
      "total_cost_usd" => 0.001,
      "usage" => %{
        "input_tokens" => 10,
        "output_tokens" => 5,
        "cache_creation_input_tokens" => 0,
        "cache_read_input_tokens" => 0,
        "server_tool_use_input_tokens" => 0
      }
    }

    {:ok, server} = MockSidecar.start(messages: [assistant_msg, result_msg])
    %{port: server.port, server_pid: server.pid}
  end

  test "connects, sends init, receives ready, sends query, receives messages", %{port: port} do
    session = self()

    {:ok, adapter} =
      Remote.start_link(session, [
        url: "ws://localhost:#{port}/sessions",
        auth_token: "test-token",
        workspace_id: "test-workspace"
      ])

    # Should receive provisioning status
    assert_receive {:adapter_status, :provisioning}, 1000

    # Should receive ready after init handshake
    assert_receive {:adapter_status, :ready}, 5000

    # Verify sidecar received init
    assert_receive {:sidecar_received, :init, init_msg}, 1000
    assert init_msg["protocol_version"] == 1
    assert init_msg["workspace_id"] == "test-workspace"

    # Send a query
    request_id = make_ref()
    :ok = Remote.send_query(adapter, request_id, "Say hello", [])

    # Should receive CC messages
    assert_receive {:adapter_message, ^request_id, %ClaudeCode.Message.AssistantMessage{}}, 5000
    assert_receive {:adapter_message, ^request_id, %ClaudeCode.Message.ResultMessage{}}, 5000

    # Should receive done
    assert_receive {:adapter_done, ^request_id, :completed}, 5000

    # Clean up
    :ok = Remote.stop(adapter)
  end
end
```

**Step 3: Run the integration test**

Run: `mix test test/claude_code/adapter/remote_integration_test.exs --include integration`
Expected: All pass

Note: If `bandit` and `websock_adapter` aren't test deps, add them temporarily:

```elixir
# In mix.exs deps — these are already dev deps for tidewave, add :test
{:bandit, "~> 1.0", only: [:dev, :test]},
{:websock_adapter, "~> 0.5", only: [:dev, :test]},
```

Run `mix deps.get` then re-run.

**Step 4: Commit**

```
git add test/support/mock_sidecar.ex test/claude_code/adapter/remote_integration_test.exs mix.exs mix.lock
git commit -m "test: add Adapter.Remote integration test with mock sidecar"
```

---

### Task 8: Remote Adapter — Interrupt Support

**Files:**
- Modify: `lib/claude_code/adapter/remote.ex`

**Step 1: Add interrupt callback**

```elixir
  @impl Adapter
  def interrupt(adapter) do
    GenServer.call(adapter, :interrupt)
  end

  # In handle_call:
  def handle_call(:interrupt, _from, state) do
    {:ok, json} = Protocol.encode_interrupt()
    state = send_ws_frame(state, {:text, json})
    {:reply, :ok, state}
  end
```

**Step 2: Verify compilation**

Run: `mix compile`
Expected: Clean compile

**Step 3: Commit**

```
git add lib/claude_code/adapter/remote.ex
git commit -m "feat: add interrupt support to Adapter.Remote"
```

---

## Phase 3: Sidecar Package

### Task 9: Scaffold Sidecar Mix Project

**Files:**
- Create: `sidecar/mix.exs`
- Create: `sidecar/lib/claude_code/sidecar.ex`
- Create: `sidecar/lib/claude_code/sidecar/application.ex`
- Create: `sidecar/config/config.exs`
- Create: `sidecar/config/runtime.exs`
- Create: `sidecar/.formatter.exs`
- Create: `sidecar/test/test_helper.exs`

**Step 1: Create mix.exs**

```elixir
# sidecar/mix.exs
defmodule ClaudeCode.Sidecar.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :claude_code_sidecar,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
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
      {:claude_code, path: ".."},
      {:bandit, "~> 1.0"},
      {:websock_adapter, "~> 0.5"},

      # Dev/test
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted"
      ]
    ]
  end

  defp releases do
    [
      claude_code_sidecar: [
        include_executables_for: [:unix]
      ]
    ]
  end
end
```

**Step 2: Create application module**

```elixir
# sidecar/lib/claude_code/sidecar/application.ex
defmodule ClaudeCode.Sidecar.Application do
  @moduledoc false
  use Application

  require Logger

  @impl Application
  def start(_type, _args) do
    port = Application.get_env(:claude_code_sidecar, :port, 4040)

    children = [
      {Bandit,
       plug: ClaudeCode.Sidecar.Router,
       port: port,
       scheme: :http}
    ]

    Logger.info("ClaudeCode.Sidecar starting on port #{port}")

    opts = [strategy: :one_for_one, name: ClaudeCode.Sidecar.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Step 3: Create main module**

```elixir
# sidecar/lib/claude_code/sidecar.ex
defmodule ClaudeCode.Sidecar do
  @moduledoc """
  ClaudeCode Sidecar — remote agent runner for ClaudeCode sessions.

  Accepts WebSocket connections and runs local CC sessions on behalf
  of remote callers. See `ClaudeCode.Adapter.Remote` for the client side.
  """
end
```

**Step 4: Create router (Plug)**

```elixir
# sidecar/lib/claude_code/sidecar/router.ex
defmodule ClaudeCode.Sidecar.Router do
  @moduledoc false
  use Plug.Router

  plug :match
  plug :dispatch

  get "/sessions" do
    auth_token = Application.get_env(:claude_code_sidecar, :auth_token)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token == auth_token ->
        conn
        |> WebSockAdapter.upgrade(ClaudeCode.Sidecar.SessionHandler, [], [])

      _ ->
        conn
        |> send_resp(401, "Unauthorized")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
```

**Step 5: Create config files**

```elixir
# sidecar/config/config.exs
import Config

config :claude_code_sidecar,
  port: 4040,
  workspaces_root: "/tmp/claude_code_workspaces"

import_config "#{config_env()}.exs"
```

```elixir
# sidecar/config/runtime.exs
import Config

if config_env() == :prod do
  config :claude_code_sidecar,
    port: String.to_integer(System.get_env("PORT", "4040")),
    workspaces_root: System.get_env("WORKSPACES_ROOT", "/workspaces"),
    auth_token: System.fetch_env!("SIDECAR_AUTH_TOKEN")
end
```

```elixir
# sidecar/config/dev.exs
import Config

config :claude_code_sidecar,
  auth_token: "dev-token"
```

```elixir
# sidecar/config/test.exs
import Config

config :claude_code_sidecar,
  auth_token: "test-token",
  workspaces_root: System.tmp_dir!()
```

**Step 6: Create formatter and test helper**

```elixir
# sidecar/.formatter.exs
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Styler]
]
```

```elixir
# sidecar/test/test_helper.exs
ExUnit.start()
```

**Step 7: Verify it compiles**

Run: `cd sidecar && mix deps.get && mix compile`
Expected: Clean compile (Router will warn about missing SessionHandler — that's Task 11)

**Step 8: Commit**

```
git add sidecar/
git commit -m "feat: scaffold claude_code_sidecar mix project"
```

---

### Task 10: Sidecar — WorkspaceManager

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
    root = Path.join(System.tmp_dir!(), "ws_test_#{:rand.uniform(100_000)}")
    File.rm_rf!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  describe "ensure_workspace/2" do
    test "creates workspace directory", %{root: root} do
      {:ok, path} = WorkspaceManager.ensure_workspace(root, "agent-1")
      assert File.dir?(path)
      assert path == Path.join(root, "agent-1")
    end

    test "is idempotent", %{root: root} do
      {:ok, path1} = WorkspaceManager.ensure_workspace(root, "agent-1")
      {:ok, path2} = WorkspaceManager.ensure_workspace(root, "agent-1")
      assert path1 == path2
    end

    test "rejects workspace_id with path traversal", %{root: root} do
      assert {:error, :invalid_workspace_id} =
               WorkspaceManager.ensure_workspace(root, "../escape")

      assert {:error, :invalid_workspace_id} =
               WorkspaceManager.ensure_workspace(root, "foo/../../bar")
    end

    test "rejects empty workspace_id", %{root: root} do
      assert {:error, :invalid_workspace_id} =
               WorkspaceManager.ensure_workspace(root, "")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd sidecar && mix test test/claude_code_sidecar/workspace_manager_test.exs`
Expected: Compilation error

**Step 3: Write implementation**

```elixir
# sidecar/lib/claude_code/sidecar/workspace_manager.ex
defmodule ClaudeCode.Sidecar.WorkspaceManager do
  @moduledoc """
  Manages workspace directories for CC agent sessions.

  Each agent gets a persistent directory under the configured workspaces root.
  Directories are created on first use and persist across sessions.
  """

  require Logger

  @doc """
  Ensures a workspace directory exists for the given ID.

  Returns `{:ok, path}` or `{:error, reason}`.
  Rejects IDs containing path traversal sequences.
  """
  @spec ensure_workspace(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure_workspace(root, workspace_id) do
    with :ok <- validate_workspace_id(workspace_id) do
      path = Path.join(root, workspace_id)
      File.mkdir_p!(path)
      Logger.info("Workspace ready: #{path}")
      {:ok, path}
    end
  end

  defp validate_workspace_id(""), do: {:error, :invalid_workspace_id}

  defp validate_workspace_id(id) do
    if String.contains?(id, "..") or String.contains?(id, "/") do
      {:error, :invalid_workspace_id}
    else
      :ok
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `cd sidecar && mix test test/claude_code_sidecar/workspace_manager_test.exs`
Expected: All pass

**Step 5: Commit**

```
git add sidecar/lib/claude_code/sidecar/workspace_manager.ex sidecar/test/claude_code/sidecar/workspace_manager_test.exs
git commit -m "feat: add WorkspaceManager for sidecar workspace directory management"
```

---

### Task 11: Sidecar — SessionHandler (WebSocket Handler)

**Files:**
- Create: `sidecar/lib/claude_code/sidecar/session_handler.ex`
- Create: `sidecar/test/claude_code/sidecar/session_handler_test.exs`

**Step 1: Write the failing tests**

```elixir
# sidecar/test/claude_code/sidecar/session_handler_test.exs
defmodule ClaudeCode.Sidecar.SessionHandlerTest do
  use ExUnit.Case

  alias ClaudeCode.Remote.Protocol

  setup do
    # Start sidecar on random port
    port = Enum.random(10_000..60_000)

    Application.put_env(:claude_code_sidecar, :port, port)
    Application.put_env(:claude_code_sidecar, :auth_token, "test-token")
    Application.put_env(:claude_code_sidecar, :workspaces_root, System.tmp_dir!())

    # The test will use Adapter.Remote to connect
    %{port: port}
  end

  # These tests verify the SessionHandler processes init and returns ready.
  # Full integration (with real CC sessions) is out of scope — requires CC CLI.

  test "rejects connection without auth token", %{port: port} do
    # Connect without auth — should get 401
    {:ok, conn} = Mint.HTTP.connect(:http, "localhost", port)
    {:ok, conn, _ref} = Mint.WebSocket.upgrade(:http, conn, "/sessions", [])

    assert_receive_response(conn, 401)
  end

  defp assert_receive_response(conn, expected_status) do
    receive do
      message ->
        {:ok, _conn, responses} = Mint.HTTP.stream(conn, message)
        status = Enum.find_value(responses, fn
          {:status, _, s} -> s
          _ -> nil
        end)
        assert status == expected_status
    after
      2000 -> flunk("No response received")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `cd sidecar && mix test test/claude_code_sidecar/session_handler_test.exs`
Expected: Compilation error — SessionHandler not found

**Step 3: Write SessionHandler**

```elixir
# sidecar/lib/claude_code/sidecar/session_handler.ex
defmodule ClaudeCode.Sidecar.SessionHandler do
  @moduledoc """
  WebSocket handler for a single remote CC session.

  Each WebSocket connection maps to one CC session. The handler:

  1. Receives `init` message with session config
  2. Creates workspace and starts a local CC session
  3. Bridges query/message/done/error between WebSocket and CC session
  4. Cleans up CC session on disconnect
  """

  @behaviour WebSock

  alias ClaudeCode.Remote.Protocol

  require Logger

  @impl WebSock
  def init(_opts) do
    {:ok, %{cc_session: nil, workspace_path: nil, streaming_task: nil}}
  end

  @impl WebSock
  def handle_in({text, [opcode: :text]}, state) do
    case Protocol.decode(text) do
      {:ok, message} -> handle_message(message, state)
      {:error, reason} ->
        Logger.warning("Failed to decode message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl WebSock
  def handle_info({:cc_message, request_id, message_json}, state) do
    {:ok, json} = Protocol.encode_message(request_id, message_json)
    {:push, {:text, json}, state}
  end

  def handle_info({:cc_done, request_id}, state) do
    {:ok, json} = Protocol.encode_done(request_id, "completed")
    {:push, {:text, json}, %{state | streaming_task: nil}}
  end

  def handle_info({:cc_error, request_id, reason}, state) do
    {:ok, json} = Protocol.encode_error(request_id, "session_error", inspect(reason))
    {:push, {:text, json}, %{state | streaming_task: nil}}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl WebSock
  def terminate(_reason, state) do
    if state.cc_session do
      Logger.info("WebSocket disconnected — stopping CC session")
      ClaudeCode.stop(state.cc_session)
    end

    :ok
  end

  # ============================================================================
  # Protocol Message Handlers
  # ============================================================================

  defp handle_message(%{type: :init} = msg, state) do
    workspaces_root = Application.get_env(:claude_code_sidecar, :workspaces_root, "/workspaces")
    workspace_id = msg.workspace_id || generate_id()

    case ClaudeCode.Sidecar.WorkspaceManager.ensure_workspace(workspaces_root, workspace_id) do
      {:ok, workspace_path} ->
        session_opts = build_session_opts(msg, workspace_path)

        case ClaudeCode.start_link(session_opts) do
          {:ok, cc_session} ->
            # Wait briefly for adapter to become ready
            session_id = get_session_id(cc_session)
            {:ok, ready_json} = Protocol.encode_ready(session_id || workspace_id)

            {:push, {:text, ready_json},
             %{state | cc_session: cc_session, workspace_path: workspace_path}}

          {:error, reason} ->
            {:ok, error_json} =
              Protocol.encode_error("init", "session_start_failed", inspect(reason))

            {:push, {:text, error_json}, state}
        end

      {:error, reason} ->
        {:ok, error_json} =
          Protocol.encode_error("init", "workspace_failed", inspect(reason))

        {:push, {:text, error_json}, state}
    end
  end

  defp handle_message(%{type: :query, request_id: request_id, prompt: prompt, opts: opts}, state) do
    ws_pid = self()
    query_opts = if opts, do: atomize_keys(opts), else: []

    task =
      Task.start(fn ->
        state.cc_session
        |> ClaudeCode.stream(prompt, query_opts)
        |> Stream.each(fn message ->
          # Encode the message back to the JSON format the parser expects
          message_json = ClaudeCode.JSONEncoder.encode(message)
          send(ws_pid, {:cc_message, request_id, message_json})
        end)
        |> Stream.run()

        send(ws_pid, {:cc_done, request_id})
      rescue
        error ->
          send(ws_pid, {:cc_error, request_id, error})
      end)

    {:ok, %{state | streaming_task: task}}
  end

  defp handle_message(%{type: :interrupt}, state) do
    if state.cc_session do
      ClaudeCode.interrupt(state.cc_session)
    end

    {:ok, state}
  end

  defp handle_message(%{type: :stop}, state) do
    if state.cc_session do
      ClaudeCode.stop(state.cc_session)
    end

    {:stop, :normal, state}
  end

  defp handle_message(_msg, state) do
    {:ok, state}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp build_session_opts(msg, workspace_path) do
    base_opts = [
      adapter: {ClaudeCode.Adapter.Local, []}
    ]

    session_opts =
      if msg.session_opts do
        msg.session_opts
        |> atomize_keys()
        |> Keyword.put(:cwd, workspace_path)
      else
        [cwd: workspace_path]
      end

    # Add resume if provided
    session_opts =
      if msg.resume do
        Keyword.put(session_opts, :resume, msg.resume)
      else
        session_opts
      end

    Keyword.merge(base_opts, session_opts)
  end

  defp get_session_id(cc_session) do
    case ClaudeCode.Session.get_session_id(cc_session) do
      {:ok, id} -> id
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp atomize_keys(map) when is_map(map) do
    Enum.map(map, fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, v}
    end)
  rescue
    # If atom doesn't exist, keep as string key — the options validator will catch it
    ArgumentError -> Map.to_list(map)
  end

  defp atomize_keys(list) when is_list(list), do: list
end
```

**Step 4: Run tests to verify they pass**

Run: `cd sidecar && mix test test/claude_code_sidecar/session_handler_test.exs`
Expected: Auth rejection test passes

**Step 5: Commit**

```
git add sidecar/lib/claude_code/sidecar/session_handler.ex sidecar/test/claude_code/sidecar/session_handler_test.exs
git commit -m "feat: add SessionHandler — WebSocket handler bridging remote connections to CC sessions"
```

---

## Phase 4: Cleanup & Quality

### Task 12: Run Quality Checks on `claude_code`

**Step 1: Run quality checks**

Run: `mix quality`
Expected: All pass. Fix any warnings or formatting issues.

**Step 2: Run tests**

Run: `mix test`
Expected: All pass (existing + new tests)

**Step 3: Fix any issues and commit**

```
git add -u
git commit -m "chore: fix quality issues from remote adapter implementation"
```

---

### Task 13: Run Quality Checks on `claude_code_sidecar`

**Step 1: Run quality checks**

Run: `cd sidecar && mix quality`
Expected: All pass.

**Step 2: Run tests**

Run: `cd sidecar && mix test`
Expected: All pass.

**Step 3: Fix any issues and commit**

```
git add -u
git commit -m "chore: fix quality issues in claude_code_sidecar"
```

---

## Implementation Notes

### Things the implementing engineer should know:

1. **Mint.WebSocket is process-less** — all state is in the `Mint.HTTP.t()` and `Mint.WebSocket.t()` structs. TCP/SSL messages arrive as regular Erlang messages to the GenServer's `handle_info/2`. See [mint_web_socket docs](https://hexdocs.pm/mint_web_socket/).

2. **The adapter uses references internally but strings on the wire** — `request_id` is a `reference()` in the Session/Adapter interface but gets serialized to a string via `inspect/1` for the WebSocket protocol. The adapter maps back using `state.request_id`.

3. **The sidecar depends on `claude_code` via `path: ".."` in dev** — for Hex release, this becomes a version dependency. The sidecar shares `ClaudeCode.Remote.Protocol` and uses `ClaudeCode.Adapter.Local` to run actual CC sessions.

4. **`bandit` is already a dev dep** in the main package (for tidewave). For tests, add it to `:test` env too. For the sidecar, it's a production dep.

5. **Built-in `JSON` module** — Elixir 1.18+ provides `JSON.encode!/1`, `JSON.decode!/1`, and `JSON.decode/1` (returns `{:ok, result} | {:error, reason}`). Use these everywhere instead of `Jason`. The `jason` dep is still needed by other parts of `claude_code` but the Protocol module should use built-in `JSON` exclusively.

6. **`ClaudeCode.JSONEncoder`** — check if this module exists. If not, messages can be re-encoded by converting structs back to maps with `Map.from_struct/1` recursively. The sidecar needs to send CC messages back as JSON maps matching the original CLI output format.

7. **`atomize_keys/1`** in SessionHandler uses `String.to_existing_atom/1` for safety. Unknown option keys will raise — the NimbleOptions validator in `ClaudeCode.Options` will catch invalid keys. Consider using `String.to_atom/1` if the sidecar is trusted.

8. **Sidecar module naming** — The package is `claude_code_sidecar` on Hex but uses the `ClaudeCode.Sidecar` module namespace (like `phoenix_live_view` uses `Phoenix.LiveView`). Files live under `sidecar/lib/claude_code/sidecar/`.

9. **TLS config** — `transport_opts(:https)` uses `:public_key.cacerts_get()` (OTP 25+). For older OTP, use the `castore` package.
