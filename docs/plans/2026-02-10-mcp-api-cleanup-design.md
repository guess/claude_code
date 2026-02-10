# MCP API Cleanup Design

## Problem

The SDK has two MCP server modules (`MCP.Server` and `MCP.Config`) that are legacy — they predate the in-process control protocol. The in-process path (`Tool.Server` → `MCP.Router` → adapter) already works end-to-end, matching the Python SDK's approach. The old modules add confusion and dead surface area.

## Changes

### Delete files

| File | Reason |
|---|---|
| `lib/claude_code/mcp/server.ex` | Hermes HTTP GenServer wrapper — not needed |
| `lib/claude_code/mcp/config.ex` | Temp file config generation — adapter builds JSON inline |
| `test/claude_code/mcp/server_test.exs` | Tests for removed module |
| `test/claude_code/mcp/config_test.exs` | Tests for removed module |

### Simplify `lib/claude_code/mcp.ex`

- Keep `available?/0` and `require_hermes!/0` (hermes_mcp is optional)
- Strip the moduledoc down: remove the architecture diagram and example code that references `MCP.Server` and `MCP.Config`
- Point users to the custom-tools guide instead

### Update `docs/guides/custom-tools.md`

- Remove the "Partial implementation" callout (in-process tools work now)
- Remove any references to `MCP.Server` or `MCP.Config`
- Keep the existing guide structure (it's already clean)

### Update `lib/claude_code/mcp/server.ex` reference in `lib/claude_code/adapter/local.ex`

- Remove `alias ClaudeCode.MCP.Server` if it existed (check — currently uses `ClaudeCode.MCP.Config`)
- Verify no compile-time references remain

### Verify no breakage

- `MCP.Router` stays untouched
- `Tool.Server` stays untouched
- `mcp_servers` option handling in `command.ex` stays untouched
- `mcp_config` option stays (direct CLI flag passthrough)
- `mix quality` passes

## What stays (the clean public API)

| Module | Role | Public? |
|---|---|---|
| `ClaudeCode.Tool.Server` | DSL for defining in-process tools | Yes |
| `ClaudeCode.MCP` | `available?/0`, `require_hermes!/0` | Yes |
| `ClaudeCode.MCP.Router` | JSONRPC dispatch | Internal |

## Out of scope

- No changes to `Tool.Server` DSL
- No changes to `mcp_servers` option handling
- No new features — pure removal
