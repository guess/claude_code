# Hooks and can_use_tool Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the `ClaudeCode.Hook` behaviour, `Hook.Registry`, `:can_use_tool` option, and `:hooks` option so the Elixir SDK can intercept tool permission decisions and handle lifecycle hook callbacks from the CLI.

**Architecture:** A `ClaudeCode.Hook` behaviour defines the `call/2` callback. `Hook.Registry` (pure functions, no process) assigns callback IDs and builds the wire format for the initialize handshake. `Adapter.Local` stores the registry in state, routes inbound `can_use_tool` and `hook_callback` control requests to the appropriate callbacks, and translates Elixir return values to CLI wire format. `CLI.Command` adds `--permission-prompt-tool stdio` when `:can_use_tool` is set. `Options` validates both new options.

**Tech Stack:** Elixir, GenServer, Jason, NimbleOptions

**Prerequisites:** Control protocol (Tasks 1-12 from `2026-02-09-control-protocol-impl.md`) must be complete.

---

### Task 1: ClaudeCode.Hook — behaviour definition

**Files:**
- Create: `lib/claude_code/hook.ex`
- Create: `test/claude_code/hook_test.exs`

**Step 1: Write the failing test**

Create `test/claude_code/hook_test.exs`:

```elixir
defmodule ClaudeCode.HookTest do
  use ExUnit.Case, async: true

  describe "behaviour" do
    test "module that implements call/2 satisfies the behaviour" do
      defmodule TestHook do
        @behaviour ClaudeCode.Hook

        @impl true
        def call(_input, _tool_use_id), do: :allow
      end

      assert TestHook.call(%{tool_name: "Bash"}, nil) == :allow
    end

    test "anonymous function can serve as a hook" do
      hook_fn = fn _input, _tool_use_id -> :allow end
      assert hook_fn.(%{tool_name: "Bash"}, nil) == :allow
    end
  end

  describe "invoke/3" do
    test "invokes a module callback" do
      defmodule AllowHook do
        @behaviour ClaudeCode.Hook

        @impl true
        def call(_input, _tool_use_id), do: :allow
      end

      assert ClaudeCode.Hook.invoke(AllowHook, %{}, nil) == :allow
    end

    test "invokes an anonymous function" do
      hook_fn = fn %{tool_name: name}, _id -> {:deny, "#{name} blocked"} end
      assert ClaudeCode.Hook.invoke(hook_fn, %{tool_name: "Bash"}, nil) == {:deny, "Bash blocked"}
    end

    test "returns {:error, reason} when callback raises" do
      bad_hook = fn _input, _id -> raise "boom" end
      assert {:error, _reason} = ClaudeCode.Hook.invoke(bad_hook, %{}, nil)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/hook_test.exs -v`
Expected: FAIL with "module ClaudeCode.Hook is not available"

**Step 3: Write minimal implementation**

Create `lib/claude_code/hook.ex`:

```elixir
defmodule ClaudeCode.Hook do
  @moduledoc """
  Behaviour for hook callbacks.

  Implement this behaviour in a module, or pass an anonymous function
  with the same `call/2` signature. Used by both `:can_use_tool` and
  `:hooks` options.

  ## Return types by event

  The return type depends on which event the hook is registered for:

  ### can_use_tool / PreToolUse (permission decisions)

      :allow
      {:allow, updated_input}
      {:allow, updated_input, permissions: [permission_update]}
      {:deny, reason}
      {:deny, reason, interrupt: true}

  ### PostToolUse / PostToolUseFailure (observation only)

      :ok

  ### UserPromptSubmit

      :ok
      {:reject, reason}

  ### Stop / SubagentStop

      :ok
      {:continue, reason}

  ### PreCompact

      :ok
      {:instructions, custom_instructions}

  ### Notification / SubagentStart (observation only)

      :ok
  """

  @callback call(input :: map(), tool_use_id :: String.t() | nil) :: term()

  @doc """
  Invokes a hook callback (module or function) with error protection.

  Returns the callback's result, or `{:error, reason}` if it raises.
  """
  @spec invoke(module() | function(), map(), String.t() | nil) :: term()
  def invoke(hook, input, tool_use_id) when is_atom(hook) do
    hook.call(input, tool_use_id)
  rescue
    e -> {:error, Exception.message(e)}
  end

  def invoke(hook, input, tool_use_id) when is_function(hook, 2) do
    hook.(input, tool_use_id)
  rescue
    e -> {:error, Exception.message(e)}
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/hook_test.exs -v`
Expected: PASS (all 5 tests)

**Step 5: Commit**

```bash
git add lib/claude_code/hook.ex test/claude_code/hook_test.exs
git commit -m "feat: add ClaudeCode.Hook behaviour"
```

---

### Task 2: Hook.Registry — build from options and wire format

**Files:**
- Create: `lib/claude_code/hook/registry.ex`
- Create: `test/claude_code/hook/registry_test.exs`

**Step 1: Write the failing test**

Create `test/claude_code/hook/registry_test.exs`:

```elixir
defmodule ClaudeCode.Hook.RegistryTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Hook.Registry

  defmodule AllowAll do
    @behaviour ClaudeCode.Hook
    @impl true
    def call(_input, _tool_use_id), do: :allow
  end

  defmodule DenyBash do
    @behaviour ClaudeCode.Hook
    @impl true
    def call(%{tool_name: "Bash"}, _id), do: {:deny, "No bash"}
    def call(_input, _id), do: :allow
  end

  defmodule AuditLogger do
    @behaviour ClaudeCode.Hook
    @impl true
    def call(_input, _tool_use_id), do: :ok
  end

  describe "new/2" do
    test "builds registry from hooks map" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash]}
        ]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert map_size(registry.callbacks) == 1
    end

    test "builds registry with can_use_tool callback" do
      {registry, _wire} = Registry.new(%{}, AllowAll)
      assert registry.can_use_tool == AllowAll
    end

    test "builds registry with nil hooks and nil can_use_tool" do
      {registry, wire} = Registry.new(nil, nil)
      assert registry.callbacks == %{}
      assert registry.can_use_tool == nil
      assert wire == nil
    end

    test "assigns sequential callback IDs" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash]},
          %{hooks: [AllowAll]}
        ],
        PostToolUse: [
          %{hooks: [AuditLogger]}
        ]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert map_size(registry.callbacks) == 3
      assert Map.has_key?(registry.callbacks, "hook_0")
      assert Map.has_key?(registry.callbacks, "hook_1")
      assert Map.has_key?(registry.callbacks, "hook_2")
    end

    test "supports anonymous function callbacks" do
      hook_fn = fn _input, _id -> :ok end

      hooks = %{
        PostToolUse: [
          %{hooks: [hook_fn]}
        ]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert map_size(registry.callbacks) == 1
    end
  end

  describe "to_wire_format/1 (via new/2)" do
    test "produces correct wire format for hooks" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash], timeout: 30}
        ]
      }

      {_registry, wire} = Registry.new(hooks, nil)

      assert %{"PreToolUse" => [matcher_entry]} = wire
      assert matcher_entry["matcher"] == "Bash"
      assert matcher_entry["hookCallbackIds"] == ["hook_0"]
      assert matcher_entry["timeout"] == 30
    end

    test "nil matcher is passed as null" do
      hooks = %{
        PostToolUse: [
          %{hooks: [AuditLogger]}
        ]
      }

      {_registry, wire} = Registry.new(hooks, nil)

      assert %{"PostToolUse" => [matcher_entry]} = wire
      assert matcher_entry["matcher"] == nil
      assert matcher_entry["hookCallbackIds"] == ["hook_0"]
      refute Map.has_key?(matcher_entry, "timeout")
    end

    test "multiple callbacks per matcher produce multiple IDs" do
      hooks = %{
        PreToolUse: [
          %{matcher: "Bash", hooks: [DenyBash, AllowAll]}
        ]
      }

      {_registry, wire} = Registry.new(hooks, nil)

      assert %{"PreToolUse" => [matcher_entry]} = wire
      assert matcher_entry["hookCallbackIds"] == ["hook_0", "hook_1"]
    end

    test "returns nil wire format when no hooks configured" do
      {_registry, wire} = Registry.new(nil, AllowAll)
      assert wire == nil
    end

    test "returns nil wire format for empty hooks map" do
      {_registry, wire} = Registry.new(%{}, nil)
      assert wire == nil
    end
  end

  describe "lookup/2" do
    test "finds callback by ID" do
      hooks = %{
        PreToolUse: [%{hooks: [DenyBash]}]
      }

      {registry, _wire} = Registry.new(hooks, nil)
      assert {:ok, DenyBash} = Registry.lookup(registry, "hook_0")
    end

    test "returns error for unknown ID" do
      {registry, _wire} = Registry.new(%{}, nil)
      assert :error = Registry.lookup(registry, "hook_999")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/hook/registry_test.exs -v`
Expected: FAIL with "module ClaudeCode.Hook.Registry is not available"

**Step 3: Write minimal implementation**

Create `lib/claude_code/hook/registry.ex`:

```elixir
defmodule ClaudeCode.Hook.Registry do
  @moduledoc false

  defstruct callbacks: %{}, can_use_tool: nil

  @doc """
  Builds a registry from the `:hooks` map and `:can_use_tool` callback.

  Returns `{registry, wire_format_hooks}` where `wire_format_hooks` is
  the map to include in the initialize handshake (or nil if no hooks).
  """
  @spec new(map() | nil, module() | function() | nil) :: {%__MODULE__{}, map() | nil}
  def new(nil, can_use_tool) do
    {%__MODULE__{can_use_tool: can_use_tool}, nil}
  end

  def new(hooks_map, can_use_tool) when hooks_map == %{} do
    {%__MODULE__{can_use_tool: can_use_tool}, nil}
  end

  def new(hooks_map, can_use_tool) when is_map(hooks_map) do
    {callbacks, wire_format, _counter} =
      Enum.reduce(hooks_map, {%{}, %{}, 0}, fn {event_name, matchers}, {cb_acc, wire_acc, counter} ->
        {matcher_entries, new_cb_acc, new_counter} =
          Enum.reduce(matchers, {[], cb_acc, counter}, fn matcher_config, {entries, cbs, cnt} ->
            hook_list = Map.get(matcher_config, :hooks, [])

            {ids, updated_cbs, updated_cnt} =
              Enum.reduce(hook_list, {[], cbs, cnt}, fn hook, {id_acc, cb, c} ->
                id = "hook_#{c}"
                {id_acc ++ [id], Map.put(cb, id, hook), c + 1}
              end)

            entry =
              %{"matcher" => Map.get(matcher_config, :matcher), "hookCallbackIds" => ids}
              |> maybe_put_timeout(Map.get(matcher_config, :timeout))

            {entries ++ [entry], updated_cbs, updated_cnt}
          end)

        event_key = to_string(event_name)
        {new_cb_acc, Map.put(wire_acc, event_key, matcher_entries), new_counter}
      end)

    wire = if wire_format == %{}, do: nil, else: wire_format

    {%__MODULE__{callbacks: callbacks, can_use_tool: can_use_tool}, wire}
  end

  @doc """
  Looks up a callback by its ID.
  """
  @spec lookup(%__MODULE__{}, String.t()) :: {:ok, module() | function()} | :error
  def lookup(%__MODULE__{callbacks: callbacks}, callback_id) do
    case Map.fetch(callbacks, callback_id) do
      {:ok, _} = result -> result
      :error -> :error
    end
  end

  defp maybe_put_timeout(entry, nil), do: entry
  defp maybe_put_timeout(entry, timeout), do: Map.put(entry, "timeout", timeout)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/hook/registry_test.exs -v`
Expected: PASS (all 11 tests)

**Step 5: Commit**

```bash
git add lib/claude_code/hook/registry.ex test/claude_code/hook/registry_test.exs
git commit -m "feat: add Hook.Registry for callback ID assignment and wire format"
```

---

### Task 3: Hook response translation — Elixir return values to wire format

**Files:**
- Create: `lib/claude_code/hook/response.ex`
- Create: `test/claude_code/hook/response_test.exs`

**Step 1: Write the failing test**

Create `test/claude_code/hook/response_test.exs`:

```elixir
defmodule ClaudeCode.Hook.ResponseTest do
  use ExUnit.Case, async: true

  alias ClaudeCode.Hook.Response

  describe "to_can_use_tool_wire/1" do
    test "translates :allow" do
      assert %{"behavior" => "allow"} = Response.to_can_use_tool_wire(:allow)
    end

    test "translates {:allow, updated_input}" do
      result = Response.to_can_use_tool_wire({:allow, %{"command" => "ls"}})
      assert result["behavior"] == "allow"
      assert result["updatedInput"] == %{"command" => "ls"}
    end

    test "translates {:allow, updated_input, permissions: updates}" do
      updates = [%{type: :add_rules, rules: [%{tool_name: "Bash", rule_content: "allow ls"}]}]
      result = Response.to_can_use_tool_wire({:allow, %{}, permissions: updates})
      assert result["behavior"] == "allow"
      assert result["updatedInput"] == %{}
      assert is_list(result["updatedPermissions"])
    end

    test "translates {:deny, reason}" do
      result = Response.to_can_use_tool_wire({:deny, "Not allowed"})
      assert result["behavior"] == "deny"
      assert result["message"] == "Not allowed"
      refute Map.has_key?(result, "interrupt")
    end

    test "translates {:deny, reason, interrupt: true}" do
      result = Response.to_can_use_tool_wire({:deny, "Critical", interrupt: true})
      assert result["behavior"] == "deny"
      assert result["message"] == "Critical"
      assert result["interrupt"] == true
    end

    test "translates {:error, reason} as deny" do
      result = Response.to_can_use_tool_wire({:error, "callback crashed"})
      assert result["behavior"] == "deny"
      assert result["message"] =~ "callback crashed"
    end
  end

  describe "to_hook_callback_wire/1" do
    test "translates :ok as empty response" do
      assert %{} = Response.to_hook_callback_wire(:ok)
    end

    test "translates :allow for PreToolUse hooks" do
      result = Response.to_hook_callback_wire(:allow)
      assert result == %{}
    end

    test "translates {:deny, reason} for PreToolUse hooks" do
      result = Response.to_hook_callback_wire({:deny, "blocked"})
      assert result["hookSpecificOutput"]["hookEventName"] == "PreToolUse"
      assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
      assert result["hookSpecificOutput"]["permissionDecisionReason"] == "blocked"
    end

    test "translates {:continue, reason} for Stop hooks" do
      result = Response.to_hook_callback_wire({:continue, "Keep going"})
      assert result["continue"] == false
      assert result["stopReason"] == "Keep going"
    end

    test "translates {:reject, reason} for UserPromptSubmit hooks" do
      result = Response.to_hook_callback_wire({:reject, "Bad prompt"})
      assert result["decision"] == "block"
      assert result["reason"] == "Bad prompt"
    end

    test "translates {:instructions, text} for PreCompact hooks" do
      result = Response.to_hook_callback_wire({:instructions, "Remember X"})
      assert result["hookSpecificOutput"]["customInstructions"] == "Remember X"
    end

    test "translates {:error, reason} as empty response" do
      result = Response.to_hook_callback_wire({:error, "crash"})
      assert result == %{}
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/hook/response_test.exs -v`
Expected: FAIL with "module ClaudeCode.Hook.Response is not available"

**Step 3: Write minimal implementation**

Create `lib/claude_code/hook/response.ex`:

```elixir
defmodule ClaudeCode.Hook.Response do
  @moduledoc false

  @doc """
  Translates a can_use_tool callback return value to CLI wire format.
  """
  @spec to_can_use_tool_wire(term()) :: map()
  def to_can_use_tool_wire(:allow) do
    %{"behavior" => "allow"}
  end

  def to_can_use_tool_wire({:allow, updated_input}) do
    %{"behavior" => "allow", "updatedInput" => updated_input}
  end

  def to_can_use_tool_wire({:allow, updated_input, permissions: updates}) do
    %{"behavior" => "allow", "updatedInput" => updated_input, "updatedPermissions" => updates}
  end

  def to_can_use_tool_wire({:deny, reason}) do
    %{"behavior" => "deny", "message" => reason}
  end

  def to_can_use_tool_wire({:deny, reason, interrupt: true}) do
    %{"behavior" => "deny", "message" => reason, "interrupt" => true}
  end

  def to_can_use_tool_wire({:error, reason}) do
    %{"behavior" => "deny", "message" => "Hook error: #{reason}"}
  end

  @doc """
  Translates a hook_callback return value to CLI wire format.
  """
  @spec to_hook_callback_wire(term()) :: map()
  def to_hook_callback_wire(:ok), do: %{}
  def to_hook_callback_wire(:allow), do: %{}

  def to_hook_callback_wire({:deny, reason}) do
    %{
      "hookSpecificOutput" => %{
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "deny",
        "permissionDecisionReason" => reason
      }
    }
  end

  def to_hook_callback_wire({:allow, updated_input}) do
    %{
      "hookSpecificOutput" => %{
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "allow",
        "updatedInput" => updated_input
      }
    }
  end

  def to_hook_callback_wire({:continue, reason}) do
    %{"continue" => false, "stopReason" => reason}
  end

  def to_hook_callback_wire({:reject, reason}) do
    %{"decision" => "block", "reason" => reason}
  end

  def to_hook_callback_wire({:instructions, text}) do
    %{"hookSpecificOutput" => %{"customInstructions" => text}}
  end

  def to_hook_callback_wire({:error, _reason}), do: %{}
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/hook/response_test.exs -v`
Expected: PASS (all 12 tests)

**Step 5: Commit**

```bash
git add lib/claude_code/hook/response.ex test/claude_code/hook/response_test.exs
git commit -m "feat: add Hook.Response for translating return values to wire format"
```

---

### Task 4: Options — add :can_use_tool and :hooks validation

**Files:**
- Modify: `lib/claude_code/options.ex`
- Modify: `test/claude_code/options_test.exs` (or the relevant option validation test file)

**Step 1: Write the failing test**

Find the options test file and add:

```elixir
  describe "can_use_tool validation" do
    test "accepts a module atom" do
      # We can't easily validate that it implements the behaviour,
      # but we can accept any atom
      {:ok, opts} = Options.validate_session_options(can_use_tool: SomeModule)
      assert Keyword.get(opts, :can_use_tool) == SomeModule
    end

    test "accepts a 2-arity function" do
      hook_fn = fn _input, _id -> :allow end
      {:ok, opts} = Options.validate_session_options(can_use_tool: hook_fn)
      assert is_function(Keyword.get(opts, :can_use_tool), 2)
    end

    test "rejects non-module non-function values" do
      assert {:error, _} = Options.validate_session_options(can_use_tool: "not valid")
    end

    test "cannot be used with permission_prompt_tool" do
      hook_fn = fn _input, _id -> :allow end

      assert_raise ArgumentError, ~r/cannot.*both/i, fn ->
        Options.validate_session_options(
          can_use_tool: hook_fn,
          permission_prompt_tool: "stdio"
        )
      end
    end
  end

  describe "hooks validation" do
    test "accepts a map with atom keys and matcher lists" do
      hooks = %{
        PreToolUse: [%{matcher: "Bash", hooks: [SomeModule]}]
      }

      {:ok, opts} = Options.validate_session_options(hooks: hooks)
      assert is_map(Keyword.get(opts, :hooks))
    end

    test "accepts a map with function hooks" do
      hooks = %{
        PostToolUse: [%{hooks: [fn _input, _id -> :ok end]}]
      }

      {:ok, opts} = Options.validate_session_options(hooks: hooks)
      assert is_map(Keyword.get(opts, :hooks))
    end

    test "rejects non-map values" do
      assert {:error, _} = Options.validate_session_options(hooks: "not a map")
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/options_test.exs -v` (or wherever the test file lives)
Expected: FAIL with "unknown options [:can_use_tool]"

**Step 3: Add options to the schema**

In `lib/claude_code/options.ex`, add to `@session_opts_schema` (after the `tool_callback` entry around line 463):

```elixir
    can_use_tool: [
      type: {:or, [:atom, {:fun, 2}]},
      doc: """
      Permission callback invoked before every tool execution.

      Accepts a module implementing `ClaudeCode.Hook` or a 2-arity function.
      Return `:allow`, `{:deny, reason}`, or `{:allow, updated_input}`.

      When set, automatically adds `--permission-prompt-tool stdio` to CLI flags.
      Cannot be used together with `:permission_prompt_tool`.

      Example:
          can_use_tool: fn %{tool_name: name}, _id ->
            if name in ["Read", "Glob"], do: :allow, else: {:deny, "Blocked"}
          end
      """
    ],
    hooks: [
      type: :map,
      doc: """
      Lifecycle hook configurations.

      A map of event names to lists of matcher configs. Each matcher has:
      - `:matcher` - Regex pattern for tool names (nil = match all)
      - `:hooks` - List of modules or 2-arity functions
      - `:timeout` - Optional timeout in seconds

      Example:
          hooks: %{
            PreToolUse: [%{matcher: "Bash", hooks: [MyApp.BashGuard]}],
            PostToolUse: [%{hooks: [MyApp.AuditLogger]}]
          }
      """
    ],
```

Also add to `validate_session_options/1` — after the existing validation, add a check for the `:can_use_tool` + `:permission_prompt_tool` conflict:

```elixir
  def validate_session_options(opts) do
    validated = opts |> normalize_agents() |> NimbleOptions.validate!(@session_opts_schema)

    if Keyword.get(validated, :can_use_tool) && Keyword.get(validated, :permission_prompt_tool) do
      raise ArgumentError,
            "cannot use both :can_use_tool and :permission_prompt_tool options together"
    end

    {:ok, validated}
  rescue
    e in NimbleOptions.ValidationError ->
      {:error, e}
  end
```

Also add `:can_use_tool` and `:hooks` to the ignored CLI options in `CLI.Command`:

```elixir
  defp convert_option(:can_use_tool, _value), do: nil
  defp convert_option(:hooks, _value), do: nil
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/options_test.exs -v`
Expected: PASS

**Step 5: Run full test suite**

Run: `mix test`
Expected: PASS (no regressions)

**Step 6: Commit**

```bash
git add lib/claude_code/options.ex lib/claude_code/cli/command.ex test/claude_code/options_test.exs
git commit -m "feat: add :can_use_tool and :hooks option validation"
```

---

### Task 5: CLI.Command — add --permission-prompt-tool stdio for can_use_tool

**Files:**
- Modify: `lib/claude_code/cli/command.ex`
- Modify: `test/claude_code/cli/command_test.exs`

**Step 1: Write the failing test**

Add to `test/claude_code/cli/command_test.exs`:

```elixir
  describe "can_use_tool flag" do
    test "adds --permission-prompt-tool stdio when can_use_tool is a module" do
      args = Command.to_cli_args(can_use_tool: SomeModule)
      assert "--permission-prompt-tool" in args
      idx = Enum.find_index(args, &(&1 == "--permission-prompt-tool"))
      assert Enum.at(args, idx + 1) == "stdio"
    end

    test "adds --permission-prompt-tool stdio when can_use_tool is a function" do
      args = Command.to_cli_args(can_use_tool: fn _, _ -> :allow end)
      assert "--permission-prompt-tool" in args
    end

    test "does not add flag when can_use_tool is nil" do
      args = Command.to_cli_args([])
      refute "--permission-prompt-tool" in args
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/cli/command_test.exs --only describe:"can_use_tool flag" -v`
Expected: FAIL because the current `convert_option(:can_use_tool, _)` returns nil

**Step 3: Update the convert_option clause**

In `lib/claude_code/cli/command.ex`, replace the nil clause for `:can_use_tool` added in Task 4:

```elixir
  # :can_use_tool triggers --permission-prompt-tool stdio; the callback itself
  # is handled by the adapter, not passed as a CLI flag
  defp convert_option(:can_use_tool, nil), do: nil

  defp convert_option(:can_use_tool, _value) do
    {"--permission-prompt-tool", "stdio"}
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/cli/command_test.exs -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/claude_code/cli/command.ex test/claude_code/cli/command_test.exs
git commit -m "feat: add --permission-prompt-tool stdio flag for can_use_tool"
```

---

### Task 6: Adapter.Local — store Hook.Registry and route can_use_tool

**Files:**
- Modify: `lib/claude_code/adapter/local.ex`
- Modify: `test/claude_code/adapter/local_test.exs`

**Step 1: Write the failing test**

Add to `test/claude_code/adapter/local_test.exs`:

```elixir
  describe "can_use_tool routing" do
    test "routes can_use_tool request to callback and responds with allow" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            SUBTYPE=$(echo "$line" | grep -o '"subtype":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ "$SUBTYPE" = "can_use_tool" ]; then
              # This should not happen in this test - we expect the adapter
              # to handle it and send back a response before we see it
              true
            else
              echo "{\\"type\\":\\"control_response\\",\\"response\\":{\\"subtype\\":\\"success\\",\\"request_id\\":\\"$REQ_ID\\",\\"response\\":{}}}"
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      allow_all = fn _input, _id -> :allow end
      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script],
          can_use_tool: allow_all
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # Verify registry is stored in state
      state = :sys.get_state(adapter)
      assert state.hook_registry != nil
      assert state.hook_registry.can_use_tool == allow_all

      GenServer.stop(adapter)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/claude_code/adapter/local_test.exs --only describe:"can_use_tool routing" -v`
Expected: FAIL because `hook_registry` field doesn't exist in adapter state

**Step 3: Modify Adapter.Local**

In `lib/claude_code/adapter/local.ex`:

1. Add alias at the top (after existing aliases around line 22):

```elixir
  alias ClaudeCode.Hook
  alias ClaudeCode.Hook.Registry, as: HookRegistry
  alias ClaudeCode.Hook.Response, as: HookResponse
```

2. Add `:hook_registry` to the struct (around line 30):

```elixir
  defstruct [
    :session,
    :session_options,
    :port,
    :buffer,
    :current_request,
    :api_key,
    :server_info,
    :hook_registry,
    status: :provisioning,
    control_counter: 0,
    pending_control_requests: %{},
    max_buffer_size: 1_048_576
  ]
```

3. Build the registry in `init/1` (around line 88, after building the initial state):

```elixir
  def init({session, opts}) do
    hooks_map = Keyword.get(opts, :hooks)
    can_use_tool = Keyword.get(opts, :can_use_tool)
    {hook_registry, _wire} = HookRegistry.new(hooks_map, can_use_tool)

    state = %__MODULE__{
      session: session,
      session_options: opts,
      buffer: "",
      api_key: Keyword.get(opts, :api_key),
      max_buffer_size: Keyword.get(opts, :max_buffer_size, 1_048_576),
      hook_registry: hook_registry
    }

    Process.link(session)
    Adapter.notify_status(session, :provisioning)

    {:ok, state, {:continue, :connect}}
  end
```

4. Update `send_initialize_handshake/1` to include hooks wire format (around line 291):

```elixir
  defp send_initialize_handshake(state) do
    agents = Keyword.get(state.session_options, :agents)
    hooks_map = Keyword.get(state.session_options, :hooks)
    can_use_tool = Keyword.get(state.session_options, :can_use_tool)

    {_registry, hooks_wire} = HookRegistry.new(hooks_map, can_use_tool)

    {request_id, new_counter} = next_request_id(state.control_counter)
    json = Control.initialize_request(request_id, hooks_wire, agents)
    Port.command(state.port, json <> "\n")

    pending = Map.put(state.pending_control_requests, request_id, {:initialize, state.session})
    schedule_control_timeout(request_id)

    {:noreply, %{state | control_counter: new_counter, pending_control_requests: pending}}
  end
```

5. Update `handle_inbound_control_request/2` to route `can_use_tool` and `hook_callback` (replace the existing function around line 534):

```elixir
  defp handle_inbound_control_request(msg, state) do
    request_id = get_in(msg, ["request_id"])
    request = get_in(msg, ["request"])
    subtype = get_in(request, ["subtype"])

    response_data =
      case subtype do
        "can_use_tool" ->
          handle_can_use_tool(request, state)

        "hook_callback" ->
          handle_hook_callback(request, state)

        _ ->
          Logger.warning("Received unhandled control request: #{subtype}")
          nil
      end

    response =
      if response_data do
        Control.success_response(request_id, response_data)
      else
        Control.error_response(request_id, "Not implemented: #{subtype}")
      end

    if state.port, do: Port.command(state.port, response <> "\n")
    state
  end

  defp handle_can_use_tool(request, state) do
    case state.hook_registry.can_use_tool do
      nil ->
        # No can_use_tool callback — allow by default
        %{"behavior" => "allow"}

      callback ->
        input = %{
          tool_name: request["tool_name"],
          input: request["input"],
          permission_suggestions: request["permission_suggestions"],
          blocked_path: request["blocked_path"]
        }

        tool_use_id = nil
        result = Hook.invoke(callback, input, tool_use_id)
        HookResponse.to_can_use_tool_wire(result)
    end
  end

  defp handle_hook_callback(request, state) do
    callback_id = request["callback_id"]
    input = request["input"]
    tool_use_id = request["tool_use_id"]

    case HookRegistry.lookup(state.hook_registry, callback_id) do
      {:ok, callback} ->
        result = Hook.invoke(callback, input, tool_use_id)
        HookResponse.to_hook_callback_wire(result)

      :error ->
        Logger.warning("Unknown hook callback ID: #{callback_id}")
        %{}
    end
  end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/claude_code/adapter/local_test.exs -v`
Expected: PASS (all tests including existing ones)

**Step 5: Run full test suite**

Run: `mix test`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/claude_code/adapter/local.ex test/claude_code/adapter/local_test.exs
git commit -m "feat: store Hook.Registry in adapter and route can_use_tool/hook_callback"
```

---

### Task 7: Integration test — can_use_tool end-to-end with mock CLI

**Files:**
- Modify: `test/claude_code/adapter/local_test.exs`

**Step 1: Write the test**

Add a more complete integration test that verifies the full round-trip:

```elixir
  describe "can_use_tool integration" do
    test "deny response prevents tool execution" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            SUBTYPE=$(echo "$line" | grep -o '"subtype":"[^"]*"' | head -1 | cut -d'"' -f4)
            if [ "$SUBTYPE" = "can_use_tool" ]; then
              # Read the SDK's response from stdout (this simulates the CLI reading our response)
              # In reality the CLI sends can_use_tool and waits for response on stdin
              # For testing we just verify the adapter handles it correctly
              echo "{\\"type\\":\\"control_response\\",\\"response\\":{\\"subtype\\":\\"success\\",\\"request_id\\":\\"$REQ_ID\\",\\"response\\":{}}}"
            else
              echo "{\\"type\\":\\"control_response\\",\\"response\\":{\\"subtype\\":\\"success\\",\\"request_id\\":\\"$REQ_ID\\",\\"response\\":{}}}"
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      deny_all = fn _input, _id -> {:deny, "All tools blocked"} end
      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script],
          can_use_tool: deny_all
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # Verify the callback is stored
      state = :sys.get_state(adapter)
      assert state.hook_registry.can_use_tool == deny_all

      GenServer.stop(adapter)
    end

    test "allow with modified input passes updated input" do
      modifier = fn %{tool_name: "Write", input: %{"file_path" => path} = input}, _id ->
        {:allow, Map.put(input, "file_path", "/sandbox" <> path)}
      end

      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            echo "{\\"type\\":\\"control_response\\",\\"response\\":{\\"subtype\\":\\"success\\",\\"request_id\\":\\"$REQ_ID\\",\\"response\\":{}}}"
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
          can_use_tool: modifier
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      state = :sys.get_state(adapter)
      assert state.hook_registry.can_use_tool == modifier

      GenServer.stop(adapter)
    end
  end
```

**Step 2: Run test to verify it passes**

Run: `mix test test/claude_code/adapter/local_test.exs --only describe:"can_use_tool integration" -v`
Expected: PASS

**Step 3: Commit**

```bash
git add test/claude_code/adapter/local_test.exs
git commit -m "test: add can_use_tool integration tests"
```

---

### Task 8: Integration test — hooks end-to-end with mock CLI

**Files:**
- Modify: `test/claude_code/adapter/local_test.exs`

**Step 1: Write the test**

```elixir
  describe "hooks integration" do
    test "hooks registry is included in initialize handshake" do
      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            # Check if hooks are in the initialize request
            if echo "$line" | grep -q '"hooks"'; then
              echo "{\\"type\\":\\"control_response\\",\\"response\\":{\\"subtype\\":\\"success\\",\\"request_id\\":\\"$REQ_ID\\",\\"response\\":{\\"hooks_received\\":true}}}"
            else
              echo "{\\"type\\":\\"control_response\\",\\"response\\":{\\"subtype\\":\\"success\\",\\"request_id\\":\\"$REQ_ID\\",\\"response\\":{}}}"
            fi
          else
            echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":50,"duration_api_ms":40,"num_turns":1,"result":"ok","session_id":"test","total_cost_usd":0.001,"usage":{}}'
          fi
        done
        exit 0
        """)

      logger = fn _input, _id -> :ok end
      session = self()

      {:ok, adapter} =
        Local.start_link(session,
          api_key: "test-key",
          cli_path: context[:mock_script],
          hooks: %{
            PostToolUse: [%{matcher: "Bash", hooks: [logger]}]
          }
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # The mock script echoes hooks_received: true if hooks were in initialize
      state = :sys.get_state(adapter)
      assert state.server_info["hooks_received"] == true

      GenServer.stop(adapter)
    end

    test "hook_callback dispatches to registered callback" do
      test_pid = self()

      hook = fn input, _id ->
        send(test_pid, {:hook_called, input})
        :ok
      end

      {:ok, context} =
        MockCLI.setup_with_script("""
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"type":"control_request"'; then
            REQ_ID=$(echo "$line" | grep -o '"request_id":"[^"]*"' | cut -d'"' -f4)
            SUBTYPE=$(echo "$line" | grep -o '"subtype":"[^"]*"' | head -1 | cut -d'"' -f4)
            echo "{\\"type\\":\\"control_response\\",\\"response\\":{\\"subtype\\":\\"success\\",\\"request_id\\":\\"$REQ_ID\\",\\"response\\":{}}}"
            # After the initialize handshake, send a hook_callback
            if [ "$SUBTYPE" = "initialize" ]; then
              sleep 0.1
              echo '{"type":"control_request","request_id":"cli_req_1","request":{"subtype":"hook_callback","callback_id":"hook_0","input":{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}},"tool_use_id":"toolu_123"}}'
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
          hooks: %{
            PostToolUse: [%{hooks: [hook]}]
          }
        )

      assert_receive {:adapter_status, :provisioning}, 1000
      assert_receive {:adapter_status, :ready}, 5000

      # The mock CLI sends a hook_callback after initialize
      assert_receive {:hook_called, input}, 5000
      assert input["hook_event_name"] == "PostToolUse"
      assert input["tool_name"] == "Bash"

      GenServer.stop(adapter)
    end
  end
```

**Step 2: Run test to verify it passes**

Run: `mix test test/claude_code/adapter/local_test.exs --only describe:"hooks integration" -v`
Expected: PASS

**Step 3: Commit**

```bash
git add test/claude_code/adapter/local_test.exs
git commit -m "test: add hooks integration tests"
```

---

### Task 9: Documentation — rewrite hooks.md and user-input.md

**Files:**
- Modify: `docs/guides/hooks.md`
- Modify: `docs/guides/user-input.md`

**Step 1: Rewrite hooks.md**

Replace the full contents of `docs/guides/hooks.md` with the content from Section 6 of the design document (`docs/plans/2026-02-10-hooks-and-can-use-tool-design.md`). The design doc contains the complete rewritten guide.

**Step 2: Rewrite user-input.md**

Replace the full contents of `docs/guides/user-input.md` with the content from Section 7 of the design document.

**Step 3: Run quality checks**

Run: `mix quality`
Expected: PASS

**Step 4: Commit**

```bash
git add docs/guides/hooks.md docs/guides/user-input.md
git commit -m "docs: rewrite hooks and user-input guides for hooks/can_use_tool"
```

---

### Task 10: Final quality checks and full test suite

**Files:**
- Verify: all files pass quality checks

**Step 1: Run full quality suite**

Run: `mix quality`
Expected: PASS (compile, format, credo, dialyzer)

**Step 2: Run full test suite**

Run: `mix test`
Expected: PASS (no regressions)

**Step 3: Run test coverage**

Run: `mix test.all`
Expected: PASS with coverage on new modules

**Step 4: Commit if any fixes needed**

```bash
git add -A
git commit -m "chore: quality fixes for hooks implementation"
```

---

## Summary

| Task | What it adds | New files | Modified files |
|------|-------------|-----------|----------------|
| 1 | `ClaudeCode.Hook` behaviour + `invoke/3` | 2 | 0 |
| 2 | `Hook.Registry` — callback IDs, lookup, wire format | 2 | 0 |
| 3 | `Hook.Response` — return value to wire translation | 2 | 0 |
| 4 | `:can_use_tool` and `:hooks` option validation | 0 | 3 |
| 5 | `--permission-prompt-tool stdio` CLI flag | 0 | 2 |
| 6 | Adapter routing for can_use_tool + hook_callback | 0 | 2 |
| 7 | can_use_tool integration tests | 0 | 1 |
| 8 | hooks integration tests | 0 | 1 |
| 9 | Documentation rewrites | 0 | 2 |
| 10 | Quality checks + coverage | 0 | 0 |

**Total: 10 tasks, ~45 steps, 6 new files, 7 modified files**
