# Struct Reorganization Plan

## Problem

Top-level `lib/claude_code/` has accumulated struct modules that don't belong there. Two categories need attention:

1. **Operation result structs** (`McpSetServersResult`, `RewindFilesResult`) — thin wrappers that should just be typed maps
2. **MCP domain struct** (`McpServerStatus`) — belongs in the `mcp/` namespace

## Changes

### 1. Demote `McpSetServersResult` to a typed map

**Delete:**
- `lib/claude_code/mcp_set_servers_result.ex`
- `test/claude_code/mcp_set_servers_result_test.exs`

**Create `lib/claude_code/cli/control/types.ex`** (`ClaudeCode.CLI.Control.Types`):
```elixir
@type set_servers_result :: %{
  added: [String.t()],
  removed: [String.t()],
  errors: %{String.t() => String.t()}
}

@type rewind_files_result :: %{
  can_rewind: boolean(),
  error: String.t() | nil,
  files_changed: [String.t()] | nil,
  insertions: non_neg_integer() | nil,
  deletions: non_neg_integer() | nil
}
```

**Update `adapter/port.ex`** — replace `McpSetServersResult.new(response)` with inline parsing:
```elixir
defp parse_set_servers_response(response) do
  %{
    added: response["added"] || [],
    removed: response["removed"] || [],
    errors: response["errors"] || %{}
  }
end
```

**Update `claude_code.ex`** — change `set_mcp_servers` return spec from `{:ok, map()}` to `{:ok, CLI.Control.Types.set_servers_result()}`.

### 2. Demote `RewindFilesResult` to a typed map

**Delete:**
- `lib/claude_code/rewind_files_result.ex`
- `test/claude_code/rewind_files_result_test.exs`

**Update `adapter/port.ex`** — replace `RewindFilesResult.new(response)` with inline parsing:
```elixir
defp parse_rewind_response(response) do
  %{
    can_rewind: response["canRewind"],
    error: response["error"],
    files_changed: response["filesChanged"],
    insertions: response["insertions"],
    deletions: response["deletions"]
  }
end
```

**Update `claude_code.ex`** — change `rewind_files` return spec from `{:ok, map()}` to `{:ok, CLI.Control.Types.rewind_files_result()}`.

### 3. Move `McpServerStatus` into `mcp/`

**Move:**
- `lib/claude_code/mcp_server_status.ex` → `lib/claude_code/mcp/server_status.ex`
- `test/claude_code/mcp_server_status_test.exs` → `test/claude_code/mcp/server_status_test.exs`

**Rename module:** `ClaudeCode.McpServerStatus` → `ClaudeCode.MCP.ServerStatus`

**Update references in:**
- `lib/claude_code.ex` — return specs for `get_mcp_status/1`
- `lib/claude_code/adapter/port.ex` — `McpServerStatus.new/1` call
- `test/` — any test references

### 4. Update CLAUDE.md

Update the file structure section to reflect the moves.

## Order of Operations

1. Create `cli/control/types.ex` with both result types
2. Move `McpServerStatus` → `MCP.ServerStatus` (rename + move, update refs)
3. Demote `McpSetServersResult` to typed map (delete + inline parsing in adapter/port.ex)
4. Demote `RewindFilesResult` to typed map (delete + inline parsing in adapter/port.ex)
5. Update `claude_code.ex` public API specs
6. Update CLAUDE.md
7. Run `mix quality` + `mix test`

## Not Changing

- `ModelInfo`, `AccountInfo`, `AgentInfo`, `SlashCommand` — stay top-level as domain entity structs
- `EffortLevel` — stays top-level as a shared utility
- `message/` — flat structure works fine at 21 types
- `content/` — fine at 4 types
