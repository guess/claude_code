# API Restructure: Top-Level Module Slimming

## Problem

`ClaudeCode` has grown to ~20 public functions. Control-plane operations (MCP management, model switching, introspection) clutter the primary API surface. The TypeScript SDK keeps its top-level to 4 functions and scopes operational controls to the Query object.

## Design

### `ClaudeCode` (top-level)

The "getting started" API — 4 core functions plus informational helpers:

```elixir
defmodule ClaudeCode do
  def start_link(opts \\ [])       # delegates to Session.Server
  def stream(session, prompt, opts \\ [])  # delegates to Session.stream
  def query(prompt, opts \\ [])    # convenience: start -> stream -> collect -> stop
  def stop(session)                # delegates to Session.stop

  def version()
  def cli_version()
end
```

### `ClaudeCode.Session` (public session API)

Everything you can do with a running session. Replaces the 14+ control-plane functions previously on `ClaudeCode`.

```elixir
defmodule ClaudeCode.Session do
  # Lifecycle (also delegated from top-level)
  def start_link(opts \\ [])
  def stream(session, prompt, opts \\ [])
  def stop(session)

  # Session state
  def health(session)
  def alive?(session)
  def session_id(session)          # was: get_session_id
  def clear(session)
  def interrupt(session)

  # Runtime configuration
  def set_model(session, model)
  def set_permission_mode(session, mode)

  # MCP management
  def mcp_status(session)          # was: get_mcp_status
  def mcp_reconnect(session, server_name)
  def mcp_toggle(session, server_name, enabled)
  def set_mcp_servers(session, servers)

  # Introspection
  def server_info(session)         # was: get_server_info
  def supported_commands(session)
  def supported_models(session)
  def supported_agents(session)
  def account_info(session)

  # History
  def conversation(session_or_id, opts \\ [])

  # Tasks
  def stop_task(session, task_id)

  # File checkpointing
  def rewind_files(session, user_message_id, opts \\ [])
end
```

### `ClaudeCode.Session.Server` (GenServer internals)

The current `ClaudeCode.Session` module renamed. No logic changes — just moves from `lib/claude_code/session.ex` to `lib/claude_code/session/server.ex`.

```elixir
defmodule ClaudeCode.Session.Server do
  use GenServer
  # All existing init/handle_call/handle_info callbacks unchanged
end
```

## Naming Conventions

- **Drop `get_` prefixes**: `get_session_id` -> `session_id`, `get_mcp_status` -> `mcp_status`, `get_server_info` -> `server_info`
- **Keep `set_` prefixes**: `set_model`, `set_permission_mode`, `set_max_thinking_tokens`, `set_mcp_servers` — the verb clarifies intent and avoids ambiguity with potential getters

## Migration Strategy

Hard cut (no deprecation period). Pre-1.0 library, no need for backwards compatibility shims.

## Implementation Steps

1. Rename `ClaudeCode.Session` -> `ClaudeCode.Session.Server` (move file)
2. Create new `ClaudeCode.Session` as public API module (delegates to Server)
3. Slim down `ClaudeCode` to 4 functions + version/cli_version
4. Rename `get_*` functions (drop prefix)
5. Update all tests (6 files)
6. Update docs and guides (7 files)
7. Update CLAUDE.md

## Files to Update

### Lib (source)
- `lib/claude_code.ex` — slim down to 4 functions
- `lib/claude_code/session.ex` — rename to `lib/claude_code/session/server.ex`
- New `lib/claude_code/session.ex` — public API module
- `lib/claude_code/options.ex` — update references
- `lib/claude_code/mcp/server_status.ex` — update references
- `lib/claude_code/cli/control/types.ex` — update references

### Tests (6 files)
- `test/claude_code_test.exs`
- `test/claude_code/session_test.exs`
- `test/claude_code/session_streaming_test.exs`
- `test/claude_code/session_adapter_test.exs`
- `test/claude_code/adapter/port_integration_test.exs`
- `test/fixtures/cli_messages/read_file.jsonl`

### Docs/guides (7 files)
- `docs/guides/sessions.md` — 12 references
- `docs/guides/file-checkpointing.md` — 10 references
- `docs/guides/permissions.md` — 2 references
- `docs/guides/distributed-sessions.md` — 1 reference
- `docs/guides/hosting.md` — 1 reference
- `docs/reference/troubleshooting.md` — 2 references
