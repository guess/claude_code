# Control Protocol Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the bidirectional control protocol between the Elixir SDK and the Claude CLI, enabling initialize handshakes, dynamic model/permission changes, MCP status queries, and file rewind.

**Architecture:** A new `CLI.Control` module (pure functions, no processes) handles wire format for control messages. `Adapter.Local` routes control messages separately from SDK messages, tracks pending requests with timeouts, and performs the initialize handshake on port open. `Session` and `ClaudeCode` expose new public API functions. The `:agents` option moves from CLI flag to initialize handshake.

**Tech Stack:** Elixir, GenServer, Jason, NimbleOptions

---

### Task 1: CLI.Control — classify/1 and generate_request_id/1

**Files:**
- Create: `lib/claude_code/cli/control.ex`
- Create: `test/claude_code/cli/control_test.exs`

**Step 1: Write the failing test**

Create `test/claude_code/cli/control_test.exs`:

```elixir
defmodule ClaudeCode.CLI.ControlTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.CLI.Control

  describe "classify/1" do
    test "classifies control_response messages" do
      msg = %{"type" => "control_response", "response" => %{}}
      assert {:control_response, ^msg} = Control.classify(msg)
    end

    test "classifies control_request messages" do
      msg = %{"type" => "control_request", "request_id" => "req_1", "request" => %{}}
      assert {:control_request, ^msg} = Control.classify(msg)
    end

    test "classifies regular messages" do
      msg = %{"type" => "assistant", "message" => %{}}
      assert {:message, ^msg} = Control.classify(msg)
    end

    test "classifies system messages as regular messages" do
      msg = %{"type" => "system", "subtype" => "init"}
      assert {:message, ^msg} = Control.classify(msg)
    end

    test "classifies result messages as regular messages" do
      msg = %{"type" => "result", "subtype" => "success"}
      assert {:message, ^msg} = Control.classify(msg)
    end
  end

  describe "generate_request_id/1" do
    test "generates request ID with counter prefix" do
      id = Control.generate_request_id(0)
      assert String.starts_with?(id, "req_0_")
    end

    test "generates request ID with incrementing counter" do
      id = Control.generate_request_id(42)
      assert String.starts_with?(id, "req_42_")
    end

    test "generates unique request IDs" do
      id1 = Control.generate_request_id(1)
      id2 = Control.generate_request_id(1)
      assert id1 != id2
    end

    test "includes hex suffix" do
      id = Control.generate_request_id(0)
      # Format: "req_{counter}_{hex}"
      [_req, _counter, hex] = String.split(id, "_")
      assert Regex.match?(~r/^[0-9a-f]+$/, hex)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/cli/control_test.exs -v`
Expected: FAIL with "module ClaudeCode.CLI.Control is not available"

**Step 3: Write minimal implementation**

Create `lib/claude_code/cli/control.ex`:

```elixir
defmodule ClaudeCode.CLI.Control do
  @moduledoc """
  Bidirectional control protocol for the Claude CLI.

  Builds and classifies control messages that share the stdin/stdout
  transport with regular SDK messages. Part of the CLI protocol layer.
  """

  @spec classify(map()) :: {:control_request, map()} | {:control_response, map()} | {:message, map()}
  def classify(%{"type" => "control_request"} = msg), do: {:control_request, msg}
  def classify(%{"type" => "control_response"} = msg), do: {:control_response, msg}
  def classify(msg), do: {:message, msg}

  @spec generate_request_id(non_neg_integer()) :: String.t()
  def generate_request_id(counter) do
    hex = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "req_#{counter}_#{hex}"
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/cli/control_test.exs -v`
Expected: PASS (all 8 tests)

**Step 5: Commit**

```bash
git add lib/claude_code/cli/control.ex test/claude_code/cli/control_test.exs
git commit -m "feat: add CLI.Control classify and generate_request_id"
```

---

### Task 2: CLI.Control — outbound request builders

**Files:**
- Modify: `lib/claude_code/cli/control.ex`
- Modify: `test/claude_code/cli/control_test.exs`

**Step 1: Write the failing tests**

Append to `test/claude_code/cli/control_test.exs`:

```elixir
  describe "initialize_request/3" do
    test "builds initialize request JSON" do
      json = Control.initialize_request("req_1_abc")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_1_abc"
      assert decoded["request"]["subtype"] == "initialize"
    end

    test "includes hooks when provided" do
      hooks = %{"PreToolUse" => [%{"matcher" => "Bash"}]}
      json = Control.initialize_request("req_1_abc", hooks)
      decoded = Jason.decode!(json)

      assert decoded["request"]["hooks"] == hooks
    end

    test "includes agents when provided" do
      agents = %{"reviewer" => %{"prompt" => "Review code"}}
      json = Control.initialize_request("req_1_abc", nil, agents)
      decoded = Jason.decode!(json)

      assert decoded["request"]["agents"] == agents
    end

    test "produces single-line JSON (no newlines)" do
      json = Control.initialize_request("req_1_abc")
      refute String.contains?(json, "\n")
    end
  end

  describe "set_model_request/2" do
    test "builds set_model request JSON" do
      json = Control.set_model_request("req_2_def", "claude-sonnet-4-5-20250929")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_2_def"
      assert decoded["request"]["subtype"] == "set_model"
      assert decoded["request"]["model"] == "claude-sonnet-4-5-20250929"
    end
  end

  describe "set_permission_mode_request/2" do
    test "builds set_permission_mode request JSON" do
      json = Control.set_permission_mode_request("req_3_ghi", "bypassPermissions")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_3_ghi"
      assert decoded["request"]["subtype"] == "set_permission_mode"
      assert decoded["request"]["permission_mode"] == "bypassPermissions"
    end
  end

  describe "rewind_files_request/2" do
    test "builds rewind_files request JSON" do
      json = Control.rewind_files_request("req_4_jkl", "user-msg-uuid-123")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_4_jkl"
      assert decoded["request"]["subtype"] == "rewind_files"
      assert decoded["request"]["user_message_id"] == "user-msg-uuid-123"
    end
  end

  describe "mcp_status_request/1" do
    test "builds mcp_status request JSON" do
      json = Control.mcp_status_request("req_5_mno")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_request"
      assert decoded["request_id"] == "req_5_mno"
      assert decoded["request"]["subtype"] == "mcp_status"
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/cli/control_test.exs -v`
Expected: FAIL with "undefined function initialize_request/1"

**Step 3: Write minimal implementation**

Add to `lib/claude_code/cli/control.ex`:

```elixir
  # --- Outbound Request Builders (SDK → CLI) ---

  @spec initialize_request(String.t(), map() | nil, map() | nil) :: String.t()
  def initialize_request(request_id, hooks \\ nil, agents \\ nil) do
    request =
      %{subtype: "initialize"}
      |> maybe_put(:hooks, hooks)
      |> maybe_put(:agents, agents)

    encode_control_request(request_id, request)
  end

  @spec set_model_request(String.t(), String.t()) :: String.t()
  def set_model_request(request_id, model) do
    encode_control_request(request_id, %{subtype: "set_model", model: model})
  end

  @spec set_permission_mode_request(String.t(), String.t()) :: String.t()
  def set_permission_mode_request(request_id, mode) do
    encode_control_request(request_id, %{subtype: "set_permission_mode", permission_mode: mode})
  end

  @spec rewind_files_request(String.t(), String.t()) :: String.t()
  def rewind_files_request(request_id, user_message_id) do
    encode_control_request(request_id, %{subtype: "rewind_files", user_message_id: user_message_id})
  end

  @spec mcp_status_request(String.t()) :: String.t()
  def mcp_status_request(request_id) do
    encode_control_request(request_id, %{subtype: "mcp_status"})
  end

  # --- Private Helpers ---

  defp encode_control_request(request_id, request) do
    Jason.encode!(%{type: "control_request", request_id: request_id, request: request})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/cli/control_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/claude_code/cli/control.ex test/claude_code/cli/control_test.exs
git commit -m "feat: add CLI.Control outbound request builders"
```

---

### Task 3: CLI.Control — response builders and response parsing

**Files:**
- Modify: `lib/claude_code/cli/control.ex`
- Modify: `test/claude_code/cli/control_test.exs`

**Step 1: Write the failing tests**

Append to `test/claude_code/cli/control_test.exs`:

```elixir
  describe "success_response/2" do
    test "builds success control response JSON" do
      json = Control.success_response("req_1_abc", %{status: "ok"})
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "success"
      assert decoded["response"]["request_id"] == "req_1_abc"
      assert decoded["response"]["response"]["status"] == "ok"
    end

    test "produces single-line JSON" do
      json = Control.success_response("req_1_abc", %{})
      refute String.contains?(json, "\n")
    end
  end

  describe "error_response/2" do
    test "builds error control response JSON" do
      json = Control.error_response("req_1_abc", "Not implemented: can_use_tool")
      decoded = Jason.decode!(json)

      assert decoded["type"] == "control_response"
      assert decoded["response"]["subtype"] == "error"
      assert decoded["response"]["request_id"] == "req_1_abc"
      assert decoded["response"]["error"] == "Not implemented: can_use_tool"
    end
  end

  describe "parse_control_response/1" do
    test "parses success control response" do
      msg = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "success",
          "request_id" => "req_1_abc",
          "response" => %{"model" => "claude-3"}
        }
      }

      assert {:ok, "req_1_abc", %{"model" => "claude-3"}} = Control.parse_control_response(msg)
    end

    test "parses error control response" do
      msg = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "error",
          "request_id" => "req_2_def",
          "error" => "Unknown request type"
        }
      }

      assert {:error, "req_2_def", "Unknown request type"} = Control.parse_control_response(msg)
    end

    test "returns error for missing response field" do
      msg = %{"type" => "control_response"}
      assert {:error, nil, "Invalid control response: missing response field"} = Control.parse_control_response(msg)
    end

    test "returns error for unknown subtype" do
      msg = %{
        "type" => "control_response",
        "response" => %{
          "subtype" => "unknown",
          "request_id" => "req_3_ghi"
        }
      }

      assert {:error, "req_3_ghi", "Unknown control response subtype: unknown"} =
               Control.parse_control_response(msg)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/cli/control_test.exs -v`
Expected: FAIL with "undefined function success_response/2"

**Step 3: Write minimal implementation**

Add to `lib/claude_code/cli/control.ex`:

```elixir
  # --- Response Builders (SDK → CLI, answering CLI requests) ---

  @spec success_response(String.t(), map()) :: String.t()
  def success_response(request_id, response_data) do
    Jason.encode!(%{
      type: "control_response",
      response: %{subtype: "success", request_id: request_id, response: response_data}
    })
  end

  @spec error_response(String.t(), String.t()) :: String.t()
  def error_response(request_id, error_message) do
    Jason.encode!(%{
      type: "control_response",
      response: %{subtype: "error", request_id: request_id, error: error_message}
    })
  end

  # --- Response Parsing (CLI → SDK) ---

  @spec parse_control_response(map()) :: {:ok, String.t(), map()} | {:error, String.t() | nil, String.t()}
  def parse_control_response(%{"response" => %{"subtype" => "success", "request_id" => req_id, "response" => data}}) do
    {:ok, req_id, data}
  end

  def parse_control_response(%{"response" => %{"subtype" => "error", "request_id" => req_id, "error" => error}}) do
    {:error, req_id, error}
  end

  def parse_control_response(%{"response" => %{"subtype" => subtype, "request_id" => req_id}}) do
    {:error, req_id, "Unknown control response subtype: #{subtype}"}
  end

  def parse_control_response(_) do
    {:error, nil, "Invalid control response: missing response field"}
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/cli/control_test.exs -v`
Expected: PASS

**Step 5: Run quality checks**

Run: `mix quality`
Expected: PASS (no warnings, no credo issues)

**Step 6: Commit**

```bash
git add lib/claude_code/cli/control.ex test/claude_code/cli/control_test.exs
git commit -m "feat: add CLI.Control response builders and parsing"
```

---

### Task 4: Adapter.Local — add control state fields and routing in process_line

This task modifies `Adapter.Local` to route incoming JSON through `CLI.Control.classify/1` before parsing. Control messages go to new handlers; regular messages follow the existing path.

**Files:**
- Modify: `lib/claude_code/adapter/local.ex:1-381`
- Modify: `test/claude_code/adapter/local_test.exs`

**Step 1: Write the failing tests**

Add new test `describe` blocks to `test/claude_code/adapter/local_test.exs`:

```elixir
  describe "control message routing" do
    test "control_response messages do not reach session as adapter_message" do
      # A control_response should be handled internally, not forwarded to session
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        # Immediately emit a control_response (simulating a response without request)
        echo '{"type":"control_response","response":{"subtype":"success","request_id":"req_0_test","response":{}}}'
        # Then wait for stdin
        while IFS= read -r line; do
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # We should NOT receive the control_response as an adapter_message
      refute_receive {:adapter_message, _, _}, 500

      GenServer.stop(adapter)
    end

    test "regular messages still reach session as adapter_message" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          echo '{"type":"assistant","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-3","content":[{"type":"text","text":"Hello"}],"stop_reason":null,"stop_sequence":null,"usage":{}},"parent_tool_use_id":null,"session_id":"test-123"}'
          echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test-123","total_cost_usd":0.001,"usage":{}}'
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      req_ref = make_ref()
      :ok = Local.send_query(adapter, req_ref, "hello", [])

      assert_receive {:adapter_message, ^req_ref, _msg}, 5000
      assert_receive {:adapter_done, ^req_ref, :completed}, 5000

      GenServer.stop(adapter)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/adapter/local_test.exs --only describe:"control message routing" -v`
Expected: The first test should fail because currently control_response JSON would attempt to parse as a regular message and either log an error or produce an unknown message type.

**Step 3: Modify `Adapter.Local` state and process_line**

Edit `lib/claude_code/adapter/local.ex`:

1. Add `alias ClaudeCode.CLI.Control` to the alias block (after line 21).

2. Update the struct at line 28 to add new fields:

```elixir
  defstruct [
    :session,
    :session_options,
    :port,
    :buffer,
    :current_request,
    :api_key,
    :server_info,
    status: :provisioning,
    control_counter: 0,
    pending_control_requests: %{}
  ]
```

3. Replace the three `process_line` clauses (lines 347-369) with:

```elixir
  defp process_line("", state), do: state

  defp process_line(line, state) do
    case Jason.decode(line) do
      {:ok, json} ->
        case Control.classify(json) do
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

  defp handle_sdk_message(_json, %{current_request: nil} = state) do
    state
  end

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

  defp handle_control_response(msg, state) do
    case Control.parse_control_response(msg) do
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
          {nil, _} ->
            Logger.warning("Received control error for unknown request: #{request_id}")
            state

          {from, remaining} ->
            GenServer.reply(from, {:error, error_msg})
            %{state | pending_control_requests: remaining}
        end
    end
  end

  defp handle_inbound_control_request(msg, state) do
    request_id = get_in(msg, ["request_id"])
    subtype = get_in(msg, ["request", "subtype"])
    Logger.warning("Received unhandled control request: #{subtype}")

    response = Control.error_response(request_id, "Not implemented: #{subtype}")
    if state.port, do: Port.command(state.port, response <> "\n")
    state
  end
```

4. Delete the old `parse_line/1` private function (lines 371-380) since it's replaced by the new routing.

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/adapter/local_test.exs -v`
Expected: PASS (all tests including existing ones)

**Step 5: Run full test suite**

Run: `mix test`
Expected: PASS (no regressions)

**Step 6: Commit**

```bash
git add lib/claude_code/adapter/local.ex test/claude_code/adapter/local_test.exs
git commit -m "feat: route control messages in Adapter.Local process_line"
```

---

### Task 5: Adapter.Local — outbound control request tracking and timeout

This task adds the `handle_call` for `:control_request` and `:control_timeout` handler, plus port disconnect cleanup for pending control requests.

**Files:**
- Modify: `lib/claude_code/adapter/local.ex`
- Modify: `test/claude_code/adapter/local_test.exs`

**Step 1: Write the failing tests**

Add to `test/claude_code/adapter/local_test.exs`:

```elixir
  describe "outbound control requests" do
    test "send_control_request sends control message and resolves on response" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          # Check if it's a control request
          if echo "$line" | grep -q '"type":"control_request"'; then
            # Extract request_id and echo a success response
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"status\":\"ok\"}}}"
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      assert {:ok, %{"status" => "ok"}} =
               GenServer.call(adapter, {:control_request, :mcp_status, %{}})

      GenServer.stop(adapter)
    end

    test "send_control_request returns error on error response" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"error\",\"request_id\":\"$REQ_ID\",\"error\":\"Something went wrong\"}}"
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      assert {:error, "Something went wrong"} =
               GenServer.call(adapter, {:control_request, :set_model, %{model: "opus"}})

      GenServer.stop(adapter)
    end

    test "control request times out when no response received" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        # Read but never respond to control requests
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            # Silently ignore
            true
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # Override control timeout to 200ms for fast test
      :sys.replace_state(adapter, fn state ->
        # The test will use a short timeout
        state
      end)

      # Send control request with short timeout - we'll test the timeout message directly
      # by sending a :control_timeout message after creating a pending request
      task =
        Task.async(fn ->
          GenServer.call(adapter, {:control_request, :mcp_status, %{}}, 2000)
        end)

      # Wait a bit for the request to be sent
      Process.sleep(100)

      # Manually trigger timeout
      send(adapter, {:control_timeout, get_pending_request_id(adapter)})

      assert {:error, :control_timeout} = Task.await(task)

      GenServer.stop(adapter)
    end
  end
```

And add a helper at the bottom of the test module:

```elixir
  defp get_pending_request_id(adapter) do
    state = :sys.get_state(adapter)
    state.pending_control_requests |> Map.keys() |> List.first()
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/adapter/local_test.exs --only describe:"outbound control requests" -v`
Expected: FAIL with "no function clause matching"

**Step 3: Write the implementation**

Add to `lib/claude_code/adapter/local.ex`, after the existing `handle_call(:health, ...)` clause:

```elixir
  @control_timeout 30_000

  @impl GenServer
  def handle_call({:control_request, subtype, params}, from, state) do
    case state.port do
      nil ->
        {:reply, {:error, :not_connected}, state}

      port ->
        {request_id, new_counter} = next_request_id(state.control_counter)
        json = build_control_json(subtype, request_id, params)

        Port.command(port, json <> "\n")

        pending = Map.put(state.pending_control_requests, request_id, from)
        schedule_control_timeout(request_id)

        {:noreply, %{state | control_counter: new_counter, pending_control_requests: pending}}
    end
  end

  def handle_call(:get_server_info, _from, state) do
    {:reply, {:ok, state.server_info}, state}
  end
```

Add the timeout handler, after `handle_info({port, :eof}, ...)`:

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

Update `handle_port_disconnect/2` (around line 188) to fail pending control requests:

```elixir
  defp handle_port_disconnect(state, error) do
    # Fail pending control requests
    for {_req_id, from} <- state.pending_control_requests do
      GenServer.reply(from, {:error, error})
    end

    if state.current_request do
      Adapter.notify_error(state.session, state.current_request, error)
    end

    %{state | port: nil, current_request: nil, buffer: "", status: :disconnected, pending_control_requests: %{}}
  end
```

Add private helpers:

```elixir
  defp next_request_id(counter) do
    {Control.generate_request_id(counter), counter + 1}
  end

  defp build_control_json(:initialize, request_id, params) do
    hooks = Map.get(params, :hooks)
    agents = Map.get(params, :agents)
    Control.initialize_request(request_id, hooks, agents)
  end

  defp build_control_json(:set_model, request_id, %{model: model}) do
    Control.set_model_request(request_id, model)
  end

  defp build_control_json(:set_permission_mode, request_id, %{mode: mode}) do
    Control.set_permission_mode_request(request_id, to_string(mode))
  end

  defp build_control_json(:rewind_files, request_id, %{user_message_id: id}) do
    Control.rewind_files_request(request_id, id)
  end

  defp build_control_json(:mcp_status, request_id, _params) do
    Control.mcp_status_request(request_id)
  end

  defp schedule_control_timeout(request_id) do
    Process.send_after(self(), {:control_timeout, request_id}, @control_timeout)
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/adapter/local_test.exs -v`
Expected: PASS

**Step 5: Run full test suite**

Run: `mix test`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/claude_code/adapter/local.ex test/claude_code/adapter/local_test.exs
git commit -m "feat: add outbound control request tracking and timeout in Adapter.Local"
```

---

### Task 6: Adapter.Local — initialize handshake on port open

This task changes the adapter lifecycle: after the port opens, it sends an initialize request and waits for the response before notifying `:ready`.

**Files:**
- Modify: `lib/claude_code/adapter/local.ex`
- Modify: `test/claude_code/adapter/local_test.exs`

**Step 1: Write the failing tests**

Add to `test/claude_code/adapter/local_test.exs`:

```elixir
  describe "initialize handshake" do
    test "sends initialize request after port opens and caches server_info" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"subtype":"initialize"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"commands\":[\"query\"],\"capabilities\":{\"control\":true}}}}"
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 10_000

      state = :sys.get_state(adapter)
      assert state.server_info == %{"commands" => ["query"], "capabilities" => %{"control" => true}}

      GenServer.stop(adapter)
    end

    test "transitions to error on initialize timeout" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        # Never respond to initialize
        while IFS= read -r line; do
          true
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script]
        )

      assert_receive {:adapter_status, :provisioning}, 1000

      # Trigger the initialize timeout manually for fast test
      Process.sleep(200)

      state = :sys.get_state(adapter)
      # Find the pending initialize request and trigger its timeout
      case Map.keys(state.pending_control_requests) do
        [req_id | _] -> send(adapter, {:control_timeout, req_id})
        _ -> :ok
      end

      assert_receive {:adapter_status, {:error, :initialize_timeout}}, 5000

      GenServer.stop(adapter)
    end

    test "passes agents option through initialize handshake" do
      agents = %{"reviewer" => %{"prompt" => "Review code"}}

      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"subtype":"initialize"'; then
            # Verify agents are present (rudimentary check)
            if echo "$line" | grep -q '"agents"'; then
              REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
              echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"agents_received\":true}}}"
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script],
          agents: agents
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 10_000

      state = :sys.get_state(adapter)
      assert state.server_info["agents_received"] == true

      GenServer.stop(adapter)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/adapter/local_test.exs --only describe:"initialize handshake" -v`
Expected: FAIL because `handle_info({:cli_resolved, ...})` currently notifies `:ready` immediately without handshake.

**Step 3: Modify the adapter lifecycle**

In `lib/claude_code/adapter/local.ex`, replace the `handle_info({:cli_resolved, {:ok, ...}})` clause (lines 126-136):

```elixir
  @impl GenServer
  def handle_info({:cli_resolved, {:ok, {executable, args, streaming_opts}}}, state) do
    case open_cli_port(executable, args, state, streaming_opts) do
      {:ok, port} ->
        new_state = %{state | port: port, buffer: "", status: :initializing}
        send_initialize_handshake(new_state)

      {:error, reason} ->
        Adapter.notify_status(state.session, {:error, reason})
        {:noreply, %{state | status: :disconnected}}
    end
  end
```

Add the handshake helper:

```elixir
  defp send_initialize_handshake(state) do
    agents = Keyword.get(state.session_options, :agents)

    {request_id, new_counter} = next_request_id(state.control_counter)
    json = Control.initialize_request(request_id, nil, agents)
    Port.command(state.port, json <> "\n")

    # Track the initialize request specially - on success, we notify :ready
    pending = Map.put(state.pending_control_requests, request_id, {:initialize, state.session})
    schedule_control_timeout(request_id)

    {:noreply, %{state | control_counter: new_counter, pending_control_requests: pending}}
  end
```

Update `handle_control_response/2` to handle the special initialize case:

```elixir
  defp handle_control_response(msg, state) do
    case Control.parse_control_response(msg) do
      {:ok, request_id, response} ->
        case Map.pop(state.pending_control_requests, request_id) do
          {nil, _} ->
            Logger.warning("Received control response for unknown request: #{request_id}")
            state

          {{:initialize, session}, remaining} ->
            Adapter.notify_status(session, :ready)
            %{state | pending_control_requests: remaining, server_info: response, status: :ready}

          {from, remaining} ->
            GenServer.reply(from, {:ok, response})
            %{state | pending_control_requests: remaining}
        end

      {:error, request_id, error_msg} ->
        case Map.pop(state.pending_control_requests, request_id) do
          {nil, _} ->
            Logger.warning("Received control error for unknown request: #{request_id}")
            state

          {{:initialize, session}, remaining} ->
            Adapter.notify_status(session, {:error, {:initialize_failed, error_msg}})
            %{state | pending_control_requests: remaining, status: :disconnected}

          {from, remaining} ->
            GenServer.reply(from, {:error, error_msg})
            %{state | pending_control_requests: remaining}
        end
    end
  end
```

Update the timeout handler to also handle initialize timeout:

```elixir
  def handle_info({:control_timeout, request_id}, state) do
    case Map.pop(state.pending_control_requests, request_id) do
      {nil, _} ->
        {:noreply, state}

      {{:initialize, session}, remaining} ->
        Adapter.notify_status(session, {:error, :initialize_timeout})
        {:noreply, %{state | pending_control_requests: remaining, status: :disconnected}}

      {from, remaining} ->
        GenServer.reply(from, {:error, :control_timeout})
        {:noreply, %{state | pending_control_requests: remaining}}
    end
  end
```

Also update the `ensure_connected` reconnection path to include the handshake:

```elixir
  defp ensure_connected(%{port: nil, status: :disconnected} = state) do
    case spawn_cli(state) do
      {:ok, port} ->
        # Don't notify :ready yet - wait for initialize handshake
        {:ok, %{state | port: port, buffer: "", status: :initializing}}

      {:error, reason} ->
        Logger.error("Failed to reconnect to CLI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_connected(%{status: :initializing}), do: {:error, :initializing}
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/adapter/local_test.exs -v`
Expected: PASS

**Step 5: Run full test suite**

Run: `mix test`
Expected: PASS — existing tests that use MockCLI will need their mock scripts updated to respond to initialize requests. If tests fail, update the MockCLI scripts to handle the initialize handshake (check if input contains `"control_request"` and respond with a success control_response).

**IMPORTANT:** The existing tests in `local_test.exs` under "adapter status lifecycle" use mock scripts that don't handle the initialize handshake. These will now fail because the adapter won't transition to `:ready` without an initialize response. Fix them by updating their mock scripts to handle the handshake:

```bash
#!/bin/bash
while IFS= read -r line; do
  if echo "$line" | grep -q '"type":"control_request"'; then
    REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
    echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{}}}"
  else
    echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
  fi
done
exit 0
```

Also update `MockCLI.setup/2` default script to handle the handshake pattern.

**Step 6: Commit**

```bash
git add lib/claude_code/adapter/local.ex test/claude_code/adapter/local_test.exs
git commit -m "feat: add initialize handshake to Adapter.Local lifecycle"
```

---

### Task 7: Update MockCLI to handle control protocol by default

Since the initialize handshake is now required, the MockCLI helper needs to handle control requests in all generated scripts.

**Files:**
- Modify: `test/support/mock_cli.ex`
- Verify: existing tests still pass

**Step 1: Update MockCLI.build_script/2**

Modify the private `build_script/2` function in `test/support/mock_cli.ex` to wrap message output in a control-request-aware loop:

```elixir
  defp build_script(messages, sleep) do
    message_lines =
      Enum.map_join(messages, "\n", fn msg ->
        json = encode_json(msg)
        escaped_json = String.replace(json, "'", "'\\''")

        if sleep > 0 do
          "echo '#{escaped_json}'\nsleep #{sleep}"
        else
          "echo '#{escaped_json}'"
        end
      end)

    """
    #!/bin/bash
    # Streaming mode: read from stdin and handle control/user messages
    while IFS= read -r line; do
      if echo "$line" | grep -q '"type":"control_request"'; then
        REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
        echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{}}}"
      else
        #{message_lines}
      fi
    done
    exit 0
    """
  end
```

**Step 2: Run the full test suite**

Run: `mix test`
Expected: PASS (all existing tests work with control-aware mock)

**Step 3: Commit**

```bash
git add test/support/mock_cli.ex
git commit -m "feat: update MockCLI to handle control protocol handshake"
```

---

### Task 8: Adapter behaviour — add optional control callbacks

**Files:**
- Modify: `lib/claude_code/adapter.ex`

**Step 1: Write the failing test**

Add to `test/claude_code/adapter/local_test.exs`:

```elixir
  describe "control adapter callbacks" do
    test "Adapter.Local exports send_control_request/3" do
      assert function_exported?(ClaudeCode.Adapter.Local, :send_control_request, 3)
    end

    test "Adapter.Local exports get_server_info/1" do
      assert function_exported?(ClaudeCode.Adapter.Local, :get_server_info, 1)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/adapter/local_test.exs --only describe:"control adapter callbacks" -v`
Expected: FAIL

**Step 3: Add optional callbacks to behaviour and implement in Local**

Add to `lib/claude_code/adapter.ex` (after existing callbacks, before notification helpers):

```elixir
  @doc """
  Sends a control request to the adapter and waits for a response.

  This is an optional callback — adapters that don't support the control
  protocol simply don't implement it. Use `function_exported?/3` to check.
  """
  @callback send_control_request(adapter :: pid(), subtype :: atom(), params :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Returns cached server initialization info from the control handshake.

  This is an optional callback.
  """
  @callback get_server_info(adapter :: pid()) :: {:ok, map() | nil} | {:error, term()}

  @optional_callbacks [send_control_request: 3, get_server_info: 1]
```

Add new notification helper:

```elixir
  @doc """
  Forwards an inbound control request from adapter to session.

  Used when the CLI sends a control_request (e.g., can_use_tool) that
  needs to be handled by the session or user callbacks.
  """
  @spec notify_control_request(pid(), String.t(), map()) :: :ok
  def notify_control_request(session, request_id, request) do
    send(session, {:adapter_control_request, request_id, request})
    :ok
  end
```

Add public API functions to `lib/claude_code/adapter/local.ex`:

```elixir
  @impl ClaudeCode.Adapter
  def send_control_request(adapter, subtype, params) do
    GenServer.call(adapter, {:control_request, subtype, params})
  end

  @impl ClaudeCode.Adapter
  def get_server_info(adapter) do
    GenServer.call(adapter, :get_server_info)
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/adapter/local_test.exs -v`
Expected: PASS

**Step 5: Run quality checks**

Run: `mix quality`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/claude_code/adapter.ex lib/claude_code/adapter/local.ex test/claude_code/adapter/local_test.exs
git commit -m "feat: add optional control callbacks to Adapter behaviour"
```

---

### Task 9: Session — add control request forwarding

**Files:**
- Modify: `lib/claude_code/session.ex`
- Modify: `test/claude_code/session_test.exs` (or create if it's only integration tests)

**Step 1: Write the failing test**

Add tests using the test adapter pattern. In `test/claude_code/session_test.exs` (or the appropriate test file):

```elixir
  describe "control protocol" do
    test "forwards control request to adapter" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            if echo "$line" | grep -q '"subtype":"mcp_status"'; then
              echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"servers\":[{\"name\":\"test\",\"status\":\"connected\"}]}}}"
            else
              echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{}}}"
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      {:ok, session} = ClaudeCode.start_link(cli_path: context[:mock_script], api_key: "test")

      # Wait for ready
      Process.sleep(2000)

      assert {:ok, %{"servers" => _}} = GenServer.call(session, {:control, :mcp_status, %{}})

      ClaudeCode.stop(session)
    end

    test "returns :not_supported when adapter lacks control callbacks" do
      # Use test adapter which doesn't implement send_control_request
      ClaudeCode.Test.stub(:no_control, fn _prompt, _opts ->
        [MockCLI.result_message()]
      end)

      {:ok, session} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, :no_control})

      assert {:error, :not_supported} = GenServer.call(session, {:control, :mcp_status, %{}})

      ClaudeCode.stop(session)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/session_test.exs --only describe:"control protocol" -v`
Expected: FAIL with "no function clause matching"

**Step 3: Add control handling to Session**

Add to `lib/claude_code/session.ex`, after `handle_call(:health, ...)`:

```elixir
  def handle_call({:control, subtype, params}, _from, state) do
    if supports_control?(state.adapter_module) do
      result = state.adapter_module.send_control_request(state.adapter_pid, subtype, params)
      {:reply, result, state}
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

Add to the `handle_info` section (before the catch-all):

```elixir
  def handle_info({:adapter_control_request, request_id, request}, state) do
    Logger.warning("Received unhandled control request from adapter: #{inspect(request)} (#{request_id})")
    {:noreply, state}
  end
```

Add private helper:

```elixir
  defp supports_control?(adapter_module) do
    function_exported?(adapter_module, :send_control_request, 3)
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/session_test.exs -v`
Expected: PASS

**Step 5: Run full test suite**

Run: `mix test`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/claude_code/session.ex test/claude_code/session_test.exs
git commit -m "feat: add control request forwarding in Session"
```

---

### Task 10: ClaudeCode — public API functions

**Files:**
- Modify: `lib/claude_code.ex`
- Modify: `test/claude_code_test.exs`

**Step 1: Write the failing tests**

Add to `test/claude_code_test.exs`:

```elixir
  describe "control API" do
    setup do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            SUBTYPE=$(echo "$line" | grep -o '"subtype":"[^"]*"' | head -1 | cut -d'"' -f4)
            case "$SUBTYPE" in
              mcp_status)
                echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"servers\":[]}}}"
                ;;
              set_model)
                echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"model\":\"updated\"}}}"
                ;;
              set_permission_mode)
                echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"mode\":\"updated\"}}}"
                ;;
              rewind_files)
                echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{\"rewound\":true}}}"
                ;;
              *)
                echo "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$REQ_ID\",\"response\":{}}}"
                ;;
            esac
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      {:ok, session} = ClaudeCode.start_link(cli_path: context[:mock_script], api_key: "test")
      Process.sleep(2000)

      on_exit(fn -> ClaudeCode.stop(session) end)

      {:ok, session: session}
    end

    test "set_model/2 sends set_model control request", %{session: session} do
      assert {:ok, _response} = ClaudeCode.set_model(session, "claude-sonnet-4-5-20250929")
    end

    test "set_permission_mode/2 sends set_permission_mode control request", %{session: session} do
      assert {:ok, _response} = ClaudeCode.set_permission_mode(session, :bypass_permissions)
    end

    test "get_mcp_status/1 sends mcp_status control request", %{session: session} do
      assert {:ok, %{"servers" => _}} = ClaudeCode.get_mcp_status(session)
    end

    test "get_server_info/1 returns cached server info", %{session: session} do
      assert {:ok, _info} = ClaudeCode.get_server_info(session)
    end

    test "rewind_files/2 sends rewind_files control request", %{session: session} do
      assert {:ok, _response} = ClaudeCode.rewind_files(session, "user-msg-uuid-123")
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code_test.exs --only describe:"control API" -v`
Expected: FAIL with "undefined function set_model/2"

**Step 3: Add public API functions**

Add to `lib/claude_code.ex`:

```elixir
  @doc """
  Changes the model mid-conversation.

  ## Examples

      {:ok, _} = ClaudeCode.set_model(session, "claude-sonnet-4-5-20250929")
  """
  @spec set_model(session(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_model(session, model) do
    GenServer.call(session, {:control, :set_model, %{model: model}})
  end

  @doc """
  Changes the permission mode mid-conversation.

  ## Examples

      {:ok, _} = ClaudeCode.set_permission_mode(session, :bypass_permissions)
  """
  @spec set_permission_mode(session(), atom()) :: {:ok, map()} | {:error, term()}
  def set_permission_mode(session, mode) do
    GenServer.call(session, {:control, :set_permission_mode, %{mode: mode}})
  end

  @doc """
  Queries MCP server connection status.

  ## Examples

      {:ok, %{"servers" => servers}} = ClaudeCode.get_mcp_status(session)
  """
  @spec get_mcp_status(session()) :: {:ok, map()} | {:error, term()}
  def get_mcp_status(session) do
    GenServer.call(session, {:control, :mcp_status, %{}})
  end

  @doc """
  Gets server initialization info cached from the control handshake.

  ## Examples

      {:ok, info} = ClaudeCode.get_server_info(session)
  """
  @spec get_server_info(session()) :: {:ok, map() | nil} | {:error, term()}
  def get_server_info(session) do
    GenServer.call(session, :get_server_info)
  end

  @doc """
  Rewinds tracked files to the state at a specific user message checkpoint.

  ## Examples

      {:ok, _} = ClaudeCode.rewind_files(session, "user-msg-uuid-123")
  """
  @spec rewind_files(session(), String.t()) :: {:ok, map()} | {:error, term()}
  def rewind_files(session, user_message_id) do
    GenServer.call(session, {:control, :rewind_files, %{user_message_id: user_message_id}})
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code_test.exs -v`
Expected: PASS

**Step 5: Run full test suite and quality**

Run: `mix test && mix quality`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/claude_code.ex test/claude_code_test.exs
git commit -m "feat: add control protocol public API (set_model, set_permission_mode, mcp_status, server_info, rewind_files)"
```

---

### Task 11: Move :agents from CLI flag to initialize handshake

The `:agents` option currently generates a `--agents` CLI flag. With the control protocol, agents should be passed through the initialize handshake instead (matching the Python SDK behavior).

**Files:**
- Modify: `lib/claude_code/cli/command.ex:247-250`
- Modify: `test/claude_code/cli/command_test.exs`

**Step 1: Write the failing test**

Update existing agents tests in `test/claude_code/cli/command_test.exs`:

```elixir
    test "agents option is not converted to CLI flag (sent via control protocol)" do
      opts = [
        agents: %{
          "code-reviewer" => %{
            "description" => "Reviews code",
            "prompt" => "You are a reviewer"
          }
        }
      ]

      args = Command.to_cli_args(opts)
      refute "--agents" in args
    end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/cli/command_test.exs -v`
Expected: FAIL because `:agents` currently produces `--agents` flag

**Step 3: Update the convert_option for :agents**

In `lib/claude_code/cli/command.ex`, replace the `:agents` handler (line 247-250):

```elixir
  # :agents is sent via the control protocol initialize handshake, not as a CLI flag
  defp convert_option(:agents, _value), do: nil
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/cli/command_test.exs -v`
Expected: PASS — note that the two existing agents tests that check `"--agents" in args` need to be replaced with the new test above. Delete the old "converts agents map to JSON-encoded --agents" and "converts multiple agents to JSON" tests.

**Step 5: Run full test suite**

Run: `mix test`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/claude_code/cli/command.ex test/claude_code/cli/command_test.exs
git commit -m "refactor: move agents from CLI flag to control protocol initialize handshake"
```

---

### Task 12: Final quality checks and documentation

**Files:**
- Verify: all files pass quality checks
- No new files to create (docs are in module docs)

**Step 1: Run full quality suite**

Run: `mix quality`
Expected: PASS (compile, format, credo, dialyzer)

**Step 2: Run full test suite with coverage**

Run: `mix test.all`
Expected: PASS with good coverage on new modules

**Step 3: Verify no regressions in integration tests**

Run: `mix test test/claude_code/adapter/local_integration_test.exs -v`
Expected: PASS (if these exist and use the real CLI, they should still work because the CLI supports the control protocol)

**Step 4: Final commit if any formatting fixes were needed**

```bash
git add -A
git commit -m "chore: quality fixes for control protocol implementation"
```

---

## Summary

| Task | What it adds | New files | Modified files |
|------|-------------|-----------|----------------|
| 1 | `CLI.Control` classify + request ID | 2 | 0 |
| 2 | Outbound request builders | 0 | 2 |
| 3 | Response builders + parsing | 0 | 2 |
| 4 | Adapter routing via classify | 0 | 2 |
| 5 | Outbound tracking + timeout | 0 | 2 |
| 6 | Initialize handshake | 0 | 2 |
| 7 | MockCLI control support | 0 | 1 |
| 8 | Adapter behaviour callbacks | 0 | 3 |
| 9 | Session control forwarding | 0 | 2 |
| 10 | Public API functions | 0 | 2 |
| 11 | Agents to initialize | 0 | 2 |
| 12 | Quality + coverage | 0 | 0 |

**Total: 12 tasks, ~60 steps, 2 new files, 8 modified files**
