# CLI Resolution Simplification

**Status:** In Progress

## Problem

The CLI binary resolution has too many fallback paths: option → app config → bundled → PATH → common locations. This makes it unpredictable which binary gets used, and the SDK can't guarantee version compatibility when it picks up a random global install.

## Design

Replace the multi-fallback chain with three explicit modes via the `:cli_path` option:

### Modes

| Mode | Value | Behavior |
|------|-------|----------|
| Bundled | `:bundled` (default) | Only priv/bin/. Auto-install if missing. Verify version matches `configured_version()`. Re-install on mismatch. |
| Global | `:global` | `System.find_executable("claude")` + common locations. No install. Return not found if missing. |
| Explicit | `"/path/to/claude"` | Use that exact binary. Error if not found. |

### Version Checking (Bundled Mode)

When the bundled binary exists, run `claude --version` and compare against `Installer.configured_version()`. If mismatch, re-install to get the pinned version. This ensures the SDK always uses a known-compatible CLI version.

### Option Type

```elixir
cli_path: [
  type: {:or, [{:in, [:bundled, :global]}, :string]},
  doc: "CLI binary resolution mode: :bundled (default), :global, or explicit path"
]
```

No default in the schema — `CLI.find_binary/1` defaults to `:bundled` when not specified. This preserves app config override via `config :claude_code, cli_path: :global`.

### Resolution in CLI.find_binary/1

```elixir
def find_binary(opts \\ []) do
  mode = Keyword.get(opts, :cli_path) || Application.get_env(:claude_code, :cli_path, :bundled)

  case mode do
    :bundled -> find_bundled()
    :global -> find_global()
    path when is_binary(path) -> find_explicit(path)
  end
end
```

### New Installer Function

Add `Installer.version_of/1` to check the version of a specific binary path. Used by bundled mode for version verification.

## Files Changed

| File | Change |
|------|--------|
| `lib/claude_code/options.ex` | Change `cli_path` type to accept `:bundled`, `:global`, or string |
| `lib/claude_code/cli.ex` | Rewrite `find_binary/1` with three modes, version checking for bundled |
| `lib/claude_code/installer.ex` | Add `version_of/1`, update `cli_not_found_message/0` |
| `test/claude_code/cli_test.exs` | Add tests for `:bundled` and `:global` modes |
| `test/claude_code/installer_test.exs` | Add tests for `version_of/1` |

## What's NOT Changing

- Adapter behaviour, session, or stream code
- The install mechanism itself (curl | bash to priv/bin/)
- Mix task `mix claude_code.install`
- `Installer.bin_path/0` and related functions (still used by mix task)
