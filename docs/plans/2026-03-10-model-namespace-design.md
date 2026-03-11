# Model Namespace Reorganization

## Problem

`ClaudeCode.ModelInfo`, `ClaudeCode.ModelUsage`, and `ClaudeCode.EffortLevel` are all model-related types sitting at the top level. Grouping them under `ClaudeCode.Model.*` reduces top-level clutter and makes their relationship explicit.

## Design

### Module Renames

| Current | New |
|---|---|
| `ClaudeCode.ModelInfo` | `ClaudeCode.Model.Info` |
| `ClaudeCode.ModelUsage` | `ClaudeCode.Model.Usage` |
| `ClaudeCode.EffortLevel` | `ClaudeCode.Model.Effort` |

### New: `ClaudeCode.Model` (namespace module)

```elixir
defmodule ClaudeCode.Model do
  @moduledoc "Model-related types: info, usage tracking, and effort levels."

  @type name :: String.t()
end
```

### Migration

Hard cut, no deprecation aliases. Pre-1.0 library.

## Files to Change

### Source (move + rename)

1. `lib/claude_code/model_info.ex` → `lib/claude_code/model/info.ex` (rename module to `ClaudeCode.Model.Info`)
2. `lib/claude_code/model_usage.ex` → `lib/claude_code/model/usage.ex` (rename module to `ClaudeCode.Model.Usage`)
3. `lib/claude_code/effort_level.ex` → `lib/claude_code/model/effort.ex` (rename module to `ClaudeCode.Model.Effort`)
4. New: `lib/claude_code/model.ex` — namespace module

### Source (update references)

5. `lib/claude_code/message/result_message.ex` — `ModelUsage` refs (lines 113, 160)
6. `lib/claude_code/adapter/port.ex` — `ModelInfo.new/1` ref (line 779)
7. `lib/claude_code/cli/control/types.ex` — `ModelInfo.t()` ref (line 51)
8. `lib/claude_code/session.ex` — `ModelInfo.t()` in spec (line 289)

### Tests

9. `test/claude_code/model_info_test.exs` → `test/claude_code/model/info_test.exs` (rename module + alias)

### Docs

10. `CLAUDE.md` — no current refs to these modules, but verify
11. `CHANGELOG.md` — 6 references in `[Unreleased]` section (update to new names)
12. `docs/plans/2026-03-06-control-protocol-gaps.md` — 2 refs (update)
13. `docs/plans/2026-03-07-struct-reorganization.md` — check for refs (update)

### CLI sync skill references

14. `.claude/skills/cli-sync/references/type-mapping.md` — 4 refs (update mapping table)

## Implementation Steps

1. Create `lib/claude_code/model.ex` namespace module
2. Move and rename the 3 source files (git mv + module rename)
3. Update internal references in 4 source files
4. Move and rename test file
5. Update docs and skill references
6. Run `mix quality` to verify
7. Run `mix test` to verify
