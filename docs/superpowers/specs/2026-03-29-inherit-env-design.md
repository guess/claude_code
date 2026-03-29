# Design: `:inherit_env` Option

**Date:** 2026-03-29
**PR Context:** [#42](https://github.com/guess/claude_code/pull/42), [#44](https://github.com/guess/claude_code/pull/44)
**Status:** Approved

## Problem

When the SDK spawns the CLI via `Port.open({:spawn_executable, ...})`, it currently passes the entire parent BEAM process environment to the subprocess via `System.get_env()`. In production BEAM releases this can leak dozens of irrelevant or sensitive variables (e.g., `RELEASE_COOKIE`, `PROD_POSTGRES_PASSWORD`, internal framework vars).

The Python SDK already filters out `CLAUDECODE` (a marker var set by Claude Code in shells it spawns). The Elixir SDK should offer user-controllable env inheritance with a sensible default.

## Design

### New Option: `:inherit_env`

| Field | Value |
|-------|-------|
| Type | `:all \| [String.t() \| {:prefix, String.t()}]` |
| Default | `:all` |
| Scope | Session-only (not overridable at query time) |

**Behavior:**

- `:all` (default) — inherit all system env vars from `System.get_env()`, minus `CLAUDECODE`. This matches current behavior (no breaking change) and aligns with the Python SDK.
- Explicit list — only inherit vars from system env that match an exact string or a `{:prefix, "..."}` tuple. Vars not matched are not set.
- `CLAUDECODE` is always stripped from inherited env, even with `:all`. If a user needs it, they can force it via `:env`.

**Examples:**

```elixir
# Default: inherit all system env (minus CLAUDECODE)
ClaudeCode.start_link()

# Inherit nothing from system — only SDK vars, :env, and :api_key
ClaudeCode.start_link(inherit_env: [])

# Only specific vars
ClaudeCode.start_link(inherit_env: ["PATH", "HOME", "LANG"])

# Prefix matching
ClaudeCode.start_link(inherit_env: [
  "PATH", "HOME",
  {:prefix, "CLAUDE_"},
  {:prefix, "HTTP_"}
])
```

### Modified Option: `:env`

The existing `:env` option type widens to accept `false` as a value:

| Field | Value |
|-------|-------|
| Type (current) | `{:map, :string, :string}` |
| Type (new) | `{:map, :string, {:or, [:string, {:literal, false}]}}` |

Setting a key to `false` unsets it from the final env. This leverages Erlang Port's native `:env` behavior where `{~c"KEY", false}` removes the variable.

**Examples:**

```elixir
# Inherit all, but remove one sensitive var
ClaudeCode.start_link(env: %{"RELEASE_COOKIE" => false})

# Combined: selective inherit + explicit set + removal
ClaudeCode.start_link(
  inherit_env: ["PATH", "HOME", {:prefix, "ANTHROPIC_"}],
  env: %{"MY_CONFIG" => "value", "ANTHROPIC_BETA_KEY" => false}
)
```

### Env Build Pipeline

The environment is constructed in this order (later steps override earlier):

```
System.get_env()
  |> filter by :inherit_env (always strips CLAUDECODE)
  |> Map.merge(sdk_env_vars())          # CLAUDE_CODE_ENTRYPOINT, CLAUDE_AGENT_SDK_VERSION
  |> Map.merge(user :env string values) # explicit key-value overrides
  |> maybe_put_api_key()                # ANTHROPIC_API_KEY from :api_key option
  |> maybe_put_file_checkpointing()     # CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING flag
  |> convert to charlist tuples         # false values from :env pass through to Port natively
```

SDK-injected vars (`CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_AGENT_SDK_VERSION`), the `:api_key` mapping, and file checkpointing are always applied regardless of `:inherit_env`. These are SDK internals required for the CLI to function.

The `:env` map may contain `false` values alongside strings. These coexist naturally in Elixir maps and flow through `Map.merge` without issue. The charlist conversion step handles both: string values become `{charlist, charlist}` tuples, while `false` values become `{charlist, false}` tuples that Port handles natively to unset vars.

### Debug Logging

When `:debug` is enabled and `:inherit_env` is an explicit list: log a warning for each entry (exact string or prefix) that doesn't match any system env var. This helps catch typos without noise in production.

Prefix entries that match zero vars also trigger a debug warning.

## Code Changes

### 1. `lib/claude_code/options.ex`

- Add `:inherit_env` to the session options schema with NimbleOptions validation
- Custom validator for the union type (`:all` atom or list of strings/prefix tuples)
- Widen `:env` type to accept `false` values
- Add `:inherit_env` to the session-only options list (not queryable)

### 2. `lib/claude_code/adapter/port.ex`

- Add `filter_system_env/2` function that applies `:inherit_env` filtering
  - `:all` — returns all vars minus `CLAUDECODE`
  - List — returns only vars matching exact keys or prefix tuples, always excluding `CLAUDECODE`
- Update `build_env/2` to call `filter_system_env/2` instead of raw `System.get_env()`
- Update `prepare_env/1` to handle `false` values: produce `{charlist, false}` tuples instead of converting to charlist
- Add debug logging for unmatched `:inherit_env` entries when `:debug` is set

### 3. `lib/claude_code/cli/command.ex`

- Add `convert_option` clause for `:inherit_env` that returns `nil` (not a CLI flag)

### 4. `CLAUDE.md`

- Add `:inherit_env` to the options list with type, default, and description
- Update `:env` description to note `false` value support

### 5. `docs/guides/secure-deployment.md`

- Add section on environment variable control using `:inherit_env`
- Document the `false` value in `:env` for unsetting vars
- Add to the security checklist

### 6. `docs/guides/hosting.md`

- Add guidance on `:inherit_env` for production deployments where BEAM releases carry many internal env vars

### 7. `CHANGELOG.md`

- Add entry under "Added" for `:inherit_env` option
- Add entry under "Changed" for `:env` accepting `false` values

### 8. Tests

- `test/claude_code/adapter/port_test.exs`:
  - `filter_system_env/2` with `:all` strips `CLAUDECODE`
  - `filter_system_env/2` with exact string list
  - `filter_system_env/2` with prefix tuples
  - `filter_system_env/2` with mixed list (strings + prefixes)
  - `filter_system_env/2` with empty list returns empty map
  - `build_env/2` integration: `:inherit_env` filters system env, SDK vars still present
  - `build_env/2` integration: `:env` with `false` values
  - `prepare_env/1`: `false` values produce `{charlist, false}` tuples
  - Debug logging for unmatched entries (when `:debug` is set)
  - Debug logging absent when `:debug` is not set
- `test/claude_code/options_test.exs`:
  - Validates `:inherit_env` accepts `:all`
  - Validates `:inherit_env` accepts list of strings
  - Validates `:inherit_env` accepts list with prefix tuples
  - Validates `:inherit_env` rejects invalid types
  - Validates `:env` accepts `false` values
  - Validates `:inherit_env` is session-only (rejected at query time)
