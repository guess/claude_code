# Adapter Module Organization Design

**Goal:** Reorganize CLI-specific modules under the adapter namespace so the SDK cleanly separates local CLI concerns from shared/adapter-agnostic code, enabling future adapters (remote sandbox, native API).

**Status:** Implemented.

---

## Problem

Several top-level modules (`ClaudeCode.CLI`, `ClaudeCode.Installer`) are specific to the local CLI adapter but live alongside adapter-agnostic modules. The `CLI` module does double duty: local binary resolution AND shared command building. This will cause confusion when adding remote or non-CLI adapters.

## Current Layout

```
lib/claude_code/
  adapter.ex              # Behaviour (adapter-agnostic)
  adapter/
    cli.ex                # Local CLI adapter GenServer
    test.ex               # Test adapter
  cli.ex                  # Binary resolution + command building (mixed concerns)
  installer.ex            # Binary installation (local-only)
  input.ex                # stream-json stdin format (CLI-specific)
  options.ex              # Validation + CLI flag conversion (mixed concerns)
  message.ex              # JSON message parsing (CLI-specific)
  message/                # Message types
  content.ex              # Content block parsing
  content/                # Content types
  session.ex              # Session GenServer (adapter-agnostic)
  stream.ex               # Stream utilities (adapter-agnostic)
  types.ex                # Type definitions (adapter-agnostic)
  ...
```

## Dependency Graph

```
Session (adapter-agnostic)
  └─ Options.validate_*
  └─ Adapter behaviour messages

Adapter.Local (local GenServer — currently Adapter.CLI)
  ├─ CLI.build_command        → finds binary + builds args
  ├─ Input.user_message       → formats stdin JSON
  ├─ Message.parse            → parses stdout JSON
  └─ local-only: Port, shell_escape, env, reconnect

CLI (mixed concerns)
  ├─ find_binary, validate_installation   → local-only (uses Installer)
  └─ build_command, build_args            → shared (any CLI adapter needs flags)

Installer (local-only)
  └─ standalone: download, version check, bundled path

Options (mixed concerns)
  ├─ validate_session_options, validate_query_options  → adapter-agnostic
  └─ to_cli_args                                       → CLI-specific

Mix tasks (local-only)
  ├─ claude_code.install  → Installer
  └─ claude_code.path     → CLI.find_binary
```

## Adapter Naming

Adapters are named by execution environment, not protocol:

| Adapter | Module | Description |
|---------|--------|-------------|
| Local | `Adapter.Local` | Runs CLI as a local Port subprocess |
| Sandbox | `Adapter.Sandbox` | Runs CLI in a remote container (e.g., Cloudflare) |
| API | `Adapter.API` | Direct Anthropic API calls, no CLI |
| Test | `Adapter.Test` | Mock adapter for testing (existing) |

"Local" is the distinguishing characteristic over "CLI" — a remote sandbox adapter also runs the CLI, just not locally. The protocol (CLI vs native API) is captured in the shared `CLI.*` layer, not the adapter name.

## Proposed Layout

```
lib/claude_code/
  # --- Adapter-agnostic (shared by all adapters) ---
  adapter.ex                    # Behaviour + notification helpers
  session.ex                    # Session GenServer
  stream.ex                     # Stream utilities
  options.ex                    # Option validation only (remove to_cli_args)
  types.ex                      # Shared type definitions

  # --- CLI protocol (shared by any CLI-based adapter: local, remote sandbox) ---
  cli/
    command.ex                  # build_args, required_flags, to_cli_args
    input.ex                    # stream-json stdin message builders (moved from input.ex)
    parser.ex                   # JSON → struct parsing (from message.ex parse/1 + content.ex parse/1)

  # --- Struct definitions (public API, adapter-agnostic) ---
  message/                      # AssistantMessage, ResultMessage, etc. — stay here
  content/                      # TextBlock, ToolUseBlock, etc. — stay here

  # --- Local adapter (manages a Port to a local binary) ---
  adapter/
    local.ex                    # GenServer: Port, shell, env, reconnect
    local/
      installer.ex              # Binary download/install (moved from installer.ex)
      resolver.ex               # find_binary, validate_installation (extracted from cli.ex)
    test.ex                     # Test adapter (unchanged)

lib/mix/tasks/
  claude_code.install.ex        # Uses Adapter.Local.Installer
  claude_code.path.ex           # Uses Adapter.Local.Resolver
```

## Module Mapping

| Current | Proposed | Reason |
|---------|----------|--------|
| `ClaudeCode.Adapter.CLI` | `ClaudeCode.Adapter.Local` | Named by execution environment |
| `ClaudeCode.CLI.find_binary/1` | `ClaudeCode.Adapter.Local.Resolver.find_binary/1` | Local-only concern |
| `ClaudeCode.CLI.validate_installation/1` | `ClaudeCode.Adapter.Local.Resolver.validate_installation/1` | Local-only concern |
| `ClaudeCode.CLI.build_command/4` | `ClaudeCode.CLI.Command.build/4` | Shared across CLI adapters |
| `ClaudeCode.CLI.build_args` (private) | `ClaudeCode.CLI.Command.build_args/3` | Shared flag building |
| `ClaudeCode.Installer` | `ClaudeCode.Adapter.Local.Installer` | Local-only concern |
| `ClaudeCode.Input` | `ClaudeCode.CLI.Input` | CLI protocol, not adapter-specific |
| `ClaudeCode.Options.to_cli_args/1` | `ClaudeCode.CLI.Command.to_cli_args/1` | CLI-specific flag conversion |
| `ClaudeCode.Options.validate_*` | `ClaudeCode.Options` (unchanged) | Adapter-agnostic validation |
| `ClaudeCode.Message.parse/1` | `ClaudeCode.CLI.Parser.parse_message/1` | CLI-specific JSON parsing |
| `ClaudeCode.Content.parse/1` | `ClaudeCode.CLI.Parser.parse_content/1` | CLI-specific JSON parsing |
| `ClaudeCode.Message.*` structs | `ClaudeCode.Message.*` (unchanged) | Public API, adapter-agnostic |
| `ClaudeCode.Content.*` structs | `ClaudeCode.Content.*` (unchanged) | Public API, adapter-agnostic |

## Three-Layer Architecture

```
┌─────────────────────────────────────────────────────┐
│  Adapter-Agnostic                                   │
│  Session, Stream, Options (validation), Types       │
│  Message.*, Content.* struct definitions             │
│  - No knowledge of CLI, ports, or JSON format       │
│  - Works with any adapter via Adapter behaviour     │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  CLI Protocol (shared by all CLI-based adapters)    │
│  CLI.Command, CLI.Input, CLI.Parser                 │
│  - Knows CLI flags, stream-json format, JSON msgs   │
│  - Does NOT know about local files, ports, install  │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  Local Adapter                                      │
│  Adapter.Local, Adapter.Local.Resolver, .Installer  │
│  - Port management, shell escaping, env building    │
│  - Binary download, version pinning, path resolve   │
│  - Mix tasks (install, path)                        │
└─────────────────────────────────────────────────────┘
```

Future adapters slot in at the appropriate layer:

- **Remote sandbox adapter** (`Adapter.Sandbox`) — uses CLI Protocol layer (same flags, same message format), but replaces Local layer with HTTP/WebSocket transport
- **Native API adapter** (`Adapter.API`) — bypasses CLI Protocol entirely, talks directly to Anthropic API. Session and Stream layers work unchanged.

## Session Default Adapter Change

```elixir
# Current
defp resolve_adapter(opts, callers) do
  case Keyword.get(opts, :adapter) do
    nil -> {ClaudeCode.Adapter.CLI, opts}
    ...
  end
end

# After
defp resolve_adapter(opts, callers) do
  case Keyword.get(opts, :adapter) do
    nil -> {ClaudeCode.Adapter.Local, opts}
    ...
  end
end
```

## Migration Notes

### Public API unchanged

`ClaudeCode.start_link/1`, `ClaudeCode.stream/3`, `ClaudeCode.query/2` — no changes. The reorganization is internal.

### Backward compatibility for direct module users

Anyone calling `ClaudeCode.Installer.install!()` or `ClaudeCode.CLI.find_binary()` directly would need to update. These are documented but not part of the core streaming API. Options:

1. **Delegating aliases** — Keep old modules that `defdelegate` to new locations. Remove after one major version.
2. **Hard move** — Since the SDK is pre-1.0, just move and update docs.

Recommendation: Hard move. The SDK is pre-1.0 and direct `Installer`/`CLI` usage is rare.

### Message/Content structs stay at top level

`ClaudeCode.Message.*` and `ClaudeCode.Content.*` are used extensively in user code (pattern matching on stream results). These are adapter-agnostic — any adapter would produce the same structs. Only the JSON parsing logic (`Message.parse/1`, `Content.parse/1`) moves into `CLI.Parser`.

### Mix tasks reference new modules

```elixir
# claude_code.install.ex
ClaudeCode.Installer        → ClaudeCode.Adapter.Local.Installer

# claude_code.path.ex
ClaudeCode.CLI.find_binary  → ClaudeCode.Adapter.Local.Resolver.find_binary
```

## When to Implement

Trigger any of:
- Adding a remote/sandbox adapter
- Adding a native API adapter
- The current flat layout causing confusion or merge conflicts
- Major version bump where breaking moves are acceptable

## Estimated Scope

- ~15 files moved/split
- ~10 test files updated (mostly alias changes)
- Mix tasks updated to new module paths
- Session default adapter reference updated
- CLAUDE.md and docs updated
- No behavioral changes, purely structural
