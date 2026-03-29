# `:inherit_env` Option Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `:inherit_env` session option that controls which system environment variables are inherited by the CLI subprocess, plus widen `:env` to accept `false` values for unsetting vars.

**Architecture:** A new `filter_system_env/2` function in `Adapter.Port` applies the `:inherit_env` filter before the existing merge pipeline. The function signature is `filter_system_env(sys_env, inherit_env, opts)` — sys_env first to be pipe-friendly. The `prepare_env/1` charlist conversion handles `false` values natively via Erlang Port's `:env` option. NimbleOptions validates the new option with a custom validator.

**Tech Stack:** Elixir, NimbleOptions, Erlang Port, Logger

**Spec:** `docs/superpowers/specs/2026-03-29-inherit-env-design.md`

---

### Task 1: Add `filter_system_env/2` to `Adapter.Port`

**Files:**
- Modify: `lib/claude_code/adapter/port.ex` (after `sdk_env_vars/0` in the "Testable Functions" section)
- Test: `test/claude_code/adapter/port_test.exs`

- [ ] **Step 1: Write failing tests for `filter_system_env/2`**

Add a new describe block in `test/claude_code/adapter/port_test.exs`:

```elixir
describe "filter_system_env/2" do
  test "with :all returns all system env except CLAUDECODE" do
    sys_env = %{"PATH" => "/usr/bin", "CLAUDECODE" => "1", "HOME" => "/root"}
    result = Port.filter_system_env(sys_env, :all)

    refute Map.has_key?(result, "CLAUDECODE")
    assert result["PATH"] == "/usr/bin"
    assert result["HOME"] == "/root"
  end

  test "with empty list returns empty map" do
    result = Port.filter_system_env(%{"PATH" => "/usr/bin", "HOME" => "/root"}, [])
    assert result == %{}
  end

  test "with exact string list returns only matching keys" do
    sys_env = %{"PATH" => "/usr/bin", "HOME" => "/root", "SECRET" => "abc"}
    result = Port.filter_system_env(sys_env, ["PATH", "HOME"])
    assert result == %{"PATH" => "/usr/bin", "HOME" => "/root"}
  end

  test "with prefix tuples returns matching keys" do
    sys_env = %{
      "CLAUDE_CODE_FOO" => "1",
      "CLAUDE_CODE_BAR" => "2",
      "HTTP_PROXY" => "proxy",
      "HOME" => "/root"
    }
    result = Port.filter_system_env(sys_env, [{:prefix, "CLAUDE_CODE_"}])
    assert result == %{"CLAUDE_CODE_FOO" => "1", "CLAUDE_CODE_BAR" => "2"}
  end

  test "with mixed list (strings + prefixes) returns all matches" do
    sys_env = %{
      "PATH" => "/usr/bin",
      "HTTP_PROXY" => "proxy",
      "HTTPS_PROXY" => "proxy2",
      "SECRET" => "abc"
    }
    result = Port.filter_system_env(sys_env, ["PATH", {:prefix, "HTTP"}])
    assert result == %{"PATH" => "/usr/bin", "HTTP_PROXY" => "proxy", "HTTPS_PROXY" => "proxy2"}
  end

  test "explicit list allows CLAUDECODE if listed" do
    sys_env = %{"CLAUDECODE" => "1", "PATH" => "/usr/bin"}
    result = Port.filter_system_env(sys_env, ["CLAUDECODE", "PATH"])
    assert result == %{"CLAUDECODE" => "1", "PATH" => "/usr/bin"}
  end

  test "unmatched entries are silently ignored" do
    sys_env = %{"PATH" => "/usr/bin"}
    result = Port.filter_system_env(sys_env, ["PATH", "NONEXISTENT_VAR"])
    assert result == %{"PATH" => "/usr/bin"}
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/adapter/port_test.exs --no-start -v 2>&1 | grep "filter_system_env"`
Expected: All 7 tests fail with `undefined function filter_system_env`

- [ ] **Step 3: Implement `filter_system_env/2`**

Add in `lib/claude_code/adapter/port.ex` in the "Testable Functions" section (after `sdk_env_vars/0`, before `build_env/2`):

```elixir
@doc false
def filter_system_env(sys_env, inherit_env, opts \\ [])

def filter_system_env(sys_env, :all, _opts) do
  Map.delete(sys_env, "CLAUDECODE")
end

def filter_system_env(sys_env, inherit_list, opts) when is_list(inherit_list) do
  result =
    sys_env
    |> Enum.filter(fn {key, _value} ->
      matches_inherit_list?(key, inherit_list)
    end)
    |> Map.new()

  if opts[:debug], do: log_unmatched_entries(inherit_list, sys_env)

  result
end

defp matches_inherit_list?(key, inherit_list) do
  Enum.any?(inherit_list, fn
    {:prefix, prefix} -> String.starts_with?(key, prefix)
    exact when is_binary(exact) -> key == exact
  end)
end

defp log_unmatched_entries(inherit_list, sys_env) do
  Enum.each(inherit_list, fn
    {:prefix, prefix} ->
      unless Enum.any?(sys_env, fn {key, _} -> String.starts_with?(key, prefix) end) do
        Logger.debug("inherit_env: {:prefix, #{inspect(prefix)}} — no matching system env vars")
      end

    exact when is_binary(exact) ->
      unless Map.has_key?(sys_env, exact) do
        Logger.debug("inherit_env: #{inspect(exact)} — no matching system env var")
      end
  end)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/port_test.exs --no-start -v 2>&1 | grep "filter_system_env"`
Expected: All 7 tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/claude_code/adapter/port.ex test/claude_code/adapter/port_test.exs
git commit -m "feat: add filter_system_env/2 to Adapter.Port"
```

---

### Task 2: Wire `filter_system_env/2` into `build_env/2`

**Files:**
- Modify: `lib/claude_code/adapter/port.ex:482-490` (the `build_env/2` function)
- Create: `test/claude_code/adapter/port_env_test.exs` (system env integration tests, `async: false`)

- [ ] **Step 1: Write failing tests in new `port_env_test.exs`**

Create `test/claude_code/adapter/port_env_test.exs`:

```elixir
defmodule ClaudeCode.Adapter.PortEnvTest do
  use ExUnit.Case, async: false

  alias ClaudeCode.Adapter.Port

  describe "build_env/2 with inherit_env" do
    test "with inherit_env: :all strips CLAUDECODE" do
      System.put_env("CLAUDECODE", "1")
      System.put_env("CLAUDE_CODE_TEST_INHERIT", "yes")

      try do
        env = Port.build_env([inherit_env: :all], nil)

        refute Map.has_key?(env, "CLAUDECODE")
        assert env["CLAUDE_CODE_TEST_INHERIT"] == "yes"
        assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      after
        System.delete_env("CLAUDECODE")
        System.delete_env("CLAUDE_CODE_TEST_INHERIT")
      end
    end

    test "with inherit_env: [] only has SDK vars and user env" do
      System.put_env("CLAUDE_CODE_TEST_BLOCKED", "should_not_appear")

      try do
        env = Port.build_env([inherit_env: [], env: %{"MY_VAR" => "hello"}], nil)

        refute Map.has_key?(env, "CLAUDE_CODE_TEST_BLOCKED")
        refute Map.has_key?(env, "PATH")
        assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
        assert env["CLAUDE_AGENT_SDK_VERSION"] == ClaudeCode.version()
        assert env["MY_VAR"] == "hello"
      after
        System.delete_env("CLAUDE_CODE_TEST_BLOCKED")
      end
    end

    test "with inherit_env list only inherits matching vars" do
      System.put_env("CLAUDE_CODE_TEST_ALLOWED", "yes")
      System.put_env("CLAUDE_CODE_TEST_BLOCKED", "no")

      try do
        env = Port.build_env([inherit_env: ["CLAUDE_CODE_TEST_ALLOWED"]], nil)

        assert env["CLAUDE_CODE_TEST_ALLOWED"] == "yes"
        refute Map.has_key?(env, "CLAUDE_CODE_TEST_BLOCKED")
        assert env["CLAUDE_CODE_ENTRYPOINT"] == "sdk-ex"
      after
        System.delete_env("CLAUDE_CODE_TEST_ALLOWED")
        System.delete_env("CLAUDE_CODE_TEST_BLOCKED")
      end
    end

    test "with inherit_env prefix tuples" do
      System.put_env("HTTP_PROXY", "http://proxy")
      System.put_env("HTTPS_PROXY", "https://proxy")
      System.put_env("SECRET_KEY", "should_not_appear")

      try do
        env = Port.build_env([inherit_env: [{:prefix, "HTTP"}]], nil)

        assert env["HTTP_PROXY"] == "http://proxy"
        assert env["HTTPS_PROXY"] == "https://proxy"
        refute Map.has_key?(env, "SECRET_KEY")
      after
        System.delete_env("HTTP_PROXY")
        System.delete_env("HTTPS_PROXY")
        System.delete_env("SECRET_KEY")
      end
    end

    test "default (no inherit_env) inherits all except CLAUDECODE" do
      System.put_env("CLAUDECODE", "1")
      System.put_env("CLAUDE_CODE_TEST_DEFAULT", "yes")

      try do
        env = Port.build_env([], nil)

        refute Map.has_key?(env, "CLAUDECODE")
        assert env["CLAUDE_CODE_TEST_DEFAULT"] == "yes"
      after
        System.delete_env("CLAUDECODE")
        System.delete_env("CLAUDE_CODE_TEST_DEFAULT")
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/adapter/port_env_test.exs --no-start -v`
Expected: Tests fail (current `build_env/2` doesn't filter by `:inherit_env` and doesn't strip `CLAUDECODE`)

- [ ] **Step 3: Update `build_env/2` to use `filter_system_env/2`**

Replace `build_env/2` in `lib/claude_code/adapter/port.ex`:

```elixir
@doc false
def build_env(session_options, api_key) do
  inherit_env = Keyword.get(session_options, :inherit_env, :all)
  user_env = Keyword.get(session_options, :env, %{})
  debug = Keyword.get(session_options, :debug, false)

  System.get_env()
  |> filter_system_env(inherit_env, debug: debug != false)
  |> Map.merge(sdk_env_vars())
  |> Map.merge(user_env)
  |> maybe_put_api_key(api_key)
  |> maybe_put_file_checkpointing(session_options)
end
```

Note: The pipe works because `filter_system_env(sys_env, inherit_env, opts)` takes sys_env as the first argument.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/port_env_test.exs test/claude_code/adapter/port_test.exs --no-start -v`
Expected: All tests pass (including existing `build_env/2` tests — behavior unchanged for default case minus `CLAUDECODE` stripping)

- [ ] **Step 5: Commit**

```bash
git add lib/claude_code/adapter/port.ex test/claude_code/adapter/port_env_test.exs
git commit -m "feat: wire inherit_env filtering into build_env/2"
```

---

### Task 3: Support `false` values in `:env` for unsetting vars

**Files:**
- Modify: `lib/claude_code/adapter/port.ex:461-467` (the `prepare_env/1` function)
- Test: `test/claude_code/adapter/port_test.exs`

- [ ] **Step 1: Write failing test for `false` values in env**

Add to `test/claude_code/adapter/port_test.exs`:

```elixir
describe "env with false values" do
  test "build_env passes through false values from user env" do
    env = Port.build_env([env: %{"REMOVE_ME" => false, "KEEP_ME" => "yes"}], nil)

    assert env["REMOVE_ME"] == false
    assert env["KEEP_ME"] == "yes"
  end
end
```

- [ ] **Step 2: Run test to verify it passes at build_env level**

Run: `mix test test/claude_code/adapter/port_test.exs --no-start -v 2>&1 | grep "false"`
Expected: Test passes (maps accept any value type). This confirms the pipeline doesn't reject `false`.

- [ ] **Step 3: Update `prepare_env/1` to handle `false` values**

Replace `prepare_env/1` in `lib/claude_code/adapter/port.ex`:

```elixir
defp prepare_env(state) do
  state.session_options
  |> build_env(state.api_key)
  |> Enum.map(fn
    {key, false} -> {String.to_charlist(key), false}
    {key, value} -> {String.to_charlist(key), String.to_charlist(to_string(value))}
  end)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/port_test.exs --no-start -v`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/claude_code/adapter/port.ex test/claude_code/adapter/port_test.exs
git commit -m "feat: support false values in :env for unsetting vars via Port"
```

---

### Task 4: Add debug logging tests for `filter_system_env/3`

**Files:**
- Test: `test/claude_code/adapter/port_test.exs`

The implementation was already added in Task 1. This task adds the test coverage.

- [ ] **Step 1: Write debug logging tests**

Add to `test/claude_code/adapter/port_test.exs`:

```elixir
import ExUnit.CaptureLog

describe "filter_system_env/3 debug logging" do
  test "logs warning for unmatched exact entries when debug enabled" do
    log =
      capture_log([level: :debug], fn ->
        Port.filter_system_env(%{"PATH" => "/usr/bin"}, ["PATH", "NONEXISTENT_VAR"], debug: true)
      end)

    assert log =~ "NONEXISTENT_VAR"
    assert log =~ "no matching system env"
  end

  test "logs warning for unmatched prefix entries when debug enabled" do
    log =
      capture_log([level: :debug], fn ->
        Port.filter_system_env(%{"PATH" => "/usr/bin"}, [{:prefix, "ZZZZZ_"}], debug: true)
      end)

    assert log =~ "ZZZZZ_"
    assert log =~ "no matching system env"
  end

  test "no logging when debug not enabled" do
    log =
      capture_log([level: :debug], fn ->
        Port.filter_system_env(%{"PATH" => "/usr/bin"}, ["NONEXISTENT_VAR"])
      end)

    assert log == ""
  end

  test "no logging for :all mode even with debug" do
    log =
      capture_log([level: :debug], fn ->
        Port.filter_system_env(%{"PATH" => "/usr/bin"}, :all, debug: true)
      end)

    assert log == ""
  end
end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `mix test test/claude_code/adapter/port_test.exs --no-start -v 2>&1 | grep "debug logging"`
Expected: All 4 tests pass (implementation already in place from Task 1)

Note: If `capture_log` tests are flaky with `async: true`, move them to `port_env_test.exs`.

- [ ] **Step 3: Commit**

```bash
git add test/claude_code/adapter/port_test.exs
git commit -m "test: add debug logging tests for filter_system_env/3"
```

---

### Task 5: Add `:inherit_env` to `Options` schema and `:env` type widening

**Files:**
- Modify: `lib/claude_code/options.ex:495-522` (`:env` option and add `:inherit_env`)
- Modify: `lib/claude_code/cli/command.ex:363` (add nil clause)
- Test: `test/claude_code/options_test.exs`

- [ ] **Step 1: Write failing validation tests**

Add to `test/claude_code/options_test.exs`:

```elixir
describe "inherit_env option" do
  test "accepts :all" do
    assert {:ok, opts} = ClaudeCode.Options.validate_session_options(inherit_env: :all)
    assert opts[:inherit_env] == :all
  end

  test "accepts list of strings" do
    assert {:ok, opts} = ClaudeCode.Options.validate_session_options(inherit_env: ["PATH", "HOME"])
    assert opts[:inherit_env] == ["PATH", "HOME"]
  end

  test "accepts list with prefix tuples" do
    assert {:ok, opts} =
             ClaudeCode.Options.validate_session_options(
               inherit_env: ["PATH", {:prefix, "CLAUDE_"}]
             )

    assert opts[:inherit_env] == ["PATH", {:prefix, "CLAUDE_"}]
  end

  test "accepts empty list" do
    assert {:ok, opts} = ClaudeCode.Options.validate_session_options(inherit_env: [])
    assert opts[:inherit_env] == []
  end

  test "rejects invalid types" do
    assert {:error, %NimbleOptions.ValidationError{}} =
             ClaudeCode.Options.validate_session_options(inherit_env: "PATH")
  end

  test "rejects invalid list elements" do
    assert {:error, %NimbleOptions.ValidationError{}} =
             ClaudeCode.Options.validate_session_options(inherit_env: [123])
  end

  test "rejects invalid prefix tuple format" do
    assert {:error, %NimbleOptions.ValidationError{}} =
             ClaudeCode.Options.validate_session_options(inherit_env: [{:prefix, 123}])
  end

  test "is not accepted as a query option" do
    assert {:error, %NimbleOptions.ValidationError{}} =
             ClaudeCode.Options.validate_query_options(inherit_env: :all)
  end
end

describe "env option with false values" do
  test "accepts false values to unset vars" do
    assert {:ok, opts} =
             ClaudeCode.Options.validate_session_options(
               env: %{"REMOVE" => false, "KEEP" => "value"}
             )

    assert opts[:env] == %{"REMOVE" => false, "KEEP" => "value"}
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/claude_code/options_test.exs --no-start -v 2>&1 | grep "inherit_env\|false values"`
Expected: Fail — `:inherit_env` not in schema, `:env` rejects `false`

- [ ] **Step 3: Add `:inherit_env` to `@session_opts_schema` in `options.ex`**

Add after the `:env` option definition (after line ~522):

```elixir
inherit_env: [
  type: {:custom, __MODULE__, :validate_inherit_env, []},
  default: :all,
  doc: """
  Controls which system environment variables are inherited by the CLI subprocess.

  - `:all` (default) — inherit all system env vars, minus `CLAUDECODE`
  - `[]` — inherit nothing from system env (only SDK vars, `:env`, and `:api_key`)
  - List of exact strings and/or `{:prefix, "..."}` tuples — only inherit matching vars

  `CLAUDECODE` is always stripped from inherited env when using `:all`.
  With an explicit list, `CLAUDECODE` is included if matched.

  Examples:
      inherit_env: :all
      inherit_env: []
      inherit_env: ["PATH", "HOME", {:prefix, "CLAUDE_"}, {:prefix, "HTTP_"}]
  """
],
```

- [ ] **Step 4: Widen `:env` type to accept `false` values**

Replace the `:env` entry in `@session_opts_schema`:

```elixir
env: [
  type: {:custom, __MODULE__, :validate_env, []},
  default: %{},
  doc: """
  Environment variables to merge with system environment when spawning CLI.

  String values set the variable. A value of `false` unsets the variable,
  leveraging Erlang Port's native env unsetting behavior.

  These variables override system environment variables but are overridden by
  SDK-required variables (CLAUDE_CODE_ENTRYPOINT, CLAUDE_CODE_SDK_VERSION) and
  the `:api_key` option (which sets ANTHROPIC_API_KEY).

  Merge precedence (lowest to highest):
  1. System environment variables (filtered by `:inherit_env`)
  2. User `:env` option (these values)
  3. SDK-required variables
  4. `:api_key` option

  Useful for:
  - MCP tools that need specific env vars
  - Providing PATH or other tool-specific configuration
  - Testing with custom environment
  - Unsetting sensitive vars: `env: %{"SECRET" => false}`

  Example:
      env: %{
        "MY_CUSTOM_VAR" => "value",
        "PATH" => "/custom/bin:" <> System.get_env("PATH"),
        "RELEASE_COOKIE" => false
      }
  """
],
```

- [ ] **Step 5: Add custom validators**

Add near `validate_thinking` in `options.ex`:

```elixir
@doc false
def validate_inherit_env(:all), do: {:ok, :all}

def validate_inherit_env(list) when is_list(list) do
  Enum.each(list, fn
    item when is_binary(item) -> :ok
    {:prefix, prefix} when is_binary(prefix) -> :ok
    other -> throw({:invalid_inherit_env_item, other})
  end)

  {:ok, list}
catch
  {:invalid_inherit_env_item, item} ->
    {:error,
     "expected a string or {:prefix, string} tuple in :inherit_env list, got: #{inspect(item)}"}
end

def validate_inherit_env(other) do
  {:error, "expected :all or a list of strings/{:prefix, string} tuples, got: #{inspect(other)}"}
end

@doc false
def validate_env(env) when is_map(env) do
  Enum.each(env, fn
    {key, value} when is_binary(key) and is_binary(value) -> :ok
    {key, false} when is_binary(key) -> :ok
    {key, value} -> throw({:invalid_env_entry, key, value})
  end)

  {:ok, env}
catch
  {:invalid_env_entry, key, value} ->
    {:error,
     "expected string keys with string or false values in :env, got: #{inspect(key)} => #{inspect(value)}"}
end

def validate_env(other) do
  {:error, "expected a map for :env, got: #{inspect(other)}"}
end
```

- [ ] **Step 6: Add nil clause in `command.ex`**

Add to `lib/claude_code/cli/command.ex` alongside the other nil-returning clauses (near line 363):

```elixir
defp convert_option(:inherit_env, _value), do: nil
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/claude_code/options_test.exs test/claude_code/adapter/port_test.exs --no-start -v`
Expected: All tests pass

- [ ] **Step 8: Run full test suite**

Run: `mix test --no-start`
Expected: All tests pass (no regressions)

- [ ] **Step 9: Commit**

```bash
git add lib/claude_code/options.ex lib/claude_code/cli/command.ex test/claude_code/options_test.exs
git commit -m "feat: add :inherit_env option and widen :env to accept false values"
```

---

### Task 6: Update documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/guides/secure-deployment.md`
- Modify: `docs/guides/hosting.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update CLAUDE.md options list**

Find the options list near the `:env` line. Update `:env` description and add `:inherit_env`:

Change:
```
- `:env` - Additional environment variables (map of string keys/values)
```
To:
```
- `:env` - Additional environment variables (map of string keys to string values or `false` to unset)
- `:inherit_env` - Controls system env inheritance: `:all` (default), `[]`, or list of strings/`{:prefix, "..."}` tuples
```

Also update the `build_env/2` description in the File Structure section to mention `filter_system_env/2`.

- [ ] **Step 2: Update `docs/guides/secure-deployment.md`**

Add a new section after "## API Key Management" (before "## Filesystem Configuration"):

```markdown
## Environment Variable Control

By default, the SDK passes all system environment variables from the parent BEAM process to the CLI subprocess (minus `CLAUDECODE`). In production BEAM releases, this can leak dozens of internal variables (`RELEASE_COOKIE`, framework vars, etc.).

Use `:inherit_env` to control which system vars are inherited:

```elixir
# Inherit only what the CLI needs
{:ok, session} = ClaudeCode.start_link(
  inherit_env: ["PATH", "HOME", "LANG", {:prefix, "ANTHROPIC_"}, {:prefix, "HTTP_"}]
)

# Inherit nothing from system (only SDK vars + explicit :env)
{:ok, session} = ClaudeCode.start_link(inherit_env: [])
```

Use `:env` with `false` values to unset specific vars while inheriting everything else:

```elixir
{:ok, session} = ClaudeCode.start_link(
  env: %{"RELEASE_COOKIE" => false, "MY_CONFIG" => "value"}
)
```

The `:env` option sets explicit key-value pairs (highest priority after SDK internals). The two options compose: `:inherit_env` filters what comes from the system, `:env` adds or removes on top.
```

- [ ] **Step 3: Update the production checklist in `secure-deployment.md`**

Add after the `sandbox` checklist item:
```markdown
- [ ] Use `inherit_env` to limit environment variable leakage from the BEAM process
```

- [ ] **Step 4: Update `docs/guides/hosting.md`**

Add in the "Elixir-Specific: Releases" section (after the `mix claude_code.install` code block, before "For alternative setups"):

```markdown
In BEAM releases, the runtime injects many internal environment variables (`RELEASE_*`, `BINDIR`, `EMU`, etc.). Use `:inherit_env` to prevent these from leaking to the CLI subprocess:

```elixir
{:ok, session} = ClaudeCode.start_link(
  inherit_env: ["PATH", "HOME", "LANG", {:prefix, "ANTHROPIC_"}, {:prefix, "HTTP_"}],
  api_key: System.get_env("ANTHROPIC_API_KEY")
)
```
```

- [ ] **Step 5: Update CHANGELOG.md**

Add under `## [Unreleased]`, in a new `### Added` section (before the existing `### Changed`):

```markdown
### Added

- **`:inherit_env` option** — Controls which system environment variables are inherited by the CLI subprocess. Defaults to `:all` (inherit everything except `CLAUDECODE`, matching Python SDK behavior). Set to a list of exact strings or `{:prefix, "..."}` tuples for selective inheritance, or `[]` to inherit nothing. See [Secure Deployment](docs/guides/secure-deployment.md#environment-variable-control).

- **`:env` now accepts `false` values** — Setting a key to `false` in the `:env` option unsets that variable in the CLI subprocess, leveraging Erlang Port's native env unsetting. Useful for removing sensitive inherited vars: `env: %{"RELEASE_COOKIE" => false}`.
```

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/guides/secure-deployment.md docs/guides/hosting.md CHANGELOG.md
git commit -m "docs: add inherit_env and env false value documentation"
```

---

### Task 7: Final quality check

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `mix test --no-start`
Expected: All tests pass

- [ ] **Step 2: Run quality checks**

Run: `mix quality`
Expected: All checks pass (compile, format, credo, dialyzer)

- [ ] **Step 3: Fix any issues found by quality checks**

If `mix format` needs changes, run `mix format` and commit. If `credo` flags issues, fix them. If `dialyzer` has type warnings on the new custom validators, add appropriate `@spec` annotations.

- [ ] **Step 4: Final commit if needed**

```bash
git add -A
git commit -m "chore: fix quality check issues"
```
