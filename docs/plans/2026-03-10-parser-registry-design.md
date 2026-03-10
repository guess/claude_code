# Parser Registry Override Design

**Date:** 2026-03-10
**Status:** Approved

## Problem

The CLI schema evolves: new content block types appear, new system message subtypes are added,
and existing types occasionally gain new fields. Users cannot currently adapt to these changes
without waiting for an SDK release.

## Solution

Expose all three parser dispatch maps as compile-time overrideable registries via
`Application.compile_env`. Users merge their own parsers on top of the SDK defaults in
`config.exs` — no runtime overhead, no new abstraction.

## Design

### Three registries

`ClaudeCode.CLI.Parser` currently defines three module attributes:

| Attribute | Dispatches on | Use case |
|---|---|---|
| `@message_parsers` | `"type"` field | `"assistant"`, `"user"`, `"result"`, etc. |
| `@system_parsers` | `"subtype"` field | `"init"`, `"status"`, `"hook_started"`, etc. |
| `@content_parsers` | `"type"` field | `"text"`, `"tool_use"`, `"image"`, etc. |

All three will accept user overrides via `Application.compile_env`.

### Implementation

In `CLI.Parser`, replace the bare map attributes with merged versions:

```elixir
@message_parsers Map.merge(
  %{
    "assistant" => &AssistantMessage.new/1,
    # ... existing defaults ...
  },
  Application.compile_env(:claude_code, :message_parsers, %{})
)

@system_parsers Map.merge(
  %{
    "init" => &Init.new/1,
    # ... existing defaults ...
  },
  Application.compile_env(:claude_code, :system_parsers, %{})
)

@content_parsers Map.merge(
  %{
    "text" => &TextBlock.new/1,
    # ... existing defaults ...
  },
  Application.compile_env(:claude_code, :content_parsers, %{})
)
```

The merge happens once at compile time. No runtime cost.

### User-facing API

```elixir
# config/config.exs

# (a) Override an existing type — e.g. TextBlock gained a new field
config :claude_code,
  content_parsers: %{"text" => &MyApp.EnhancedTextBlock.new/1}

# (b) Handle a new unknown type the SDK doesn't know about yet
config :claude_code,
  system_parsers: %{"new_lifecycle_event" => &MyApp.NewEvent.new/1},
  content_parsers: %{"new_block_type" => &MyApp.NewBlock.new/1}

# (c) Replace all parsers in a registry (effectively replaces the whole layer)
config :claude_code,
  content_parsers: %{
    "text" => &MyApp.TextBlock.new/1,
    "tool_use" => &MyApp.ToolUseBlock.new/1,
    # ... all types
  }
```

User-supplied parsers follow the same contract as built-in ones: accept a normalized
string-keyed map, return `{:ok, struct}` or `{:error, reason}`.

### Behaviour for unknown types

No change. Unknown types continue to be silently skipped (forward compatibility).
Once a user registers a parser for a previously-unknown type, it will be called instead
of skipped.

### `filter_type` extensibility

`ClaudeCode.Stream.filter_type/2` currently uses `message_type_matches?/2`, which
pattern-matches on known struct names. User-defined structs from custom parsers will never
match, making `filter_type` useless for user-extended types.

Fix: replace the struct pattern matching with a `:type` field check. All SDK message structs
already carry a `:type` atom field — and user structs will too if they follow the same
convention.

```elixir
# Before
defp message_type_matches?(%AssistantMessage{}, :assistant), do: true
defp message_type_matches?(%ResultMessage{}, :result), do: true
# ... 10 more clauses ...
defp message_type_matches?(_, _), do: false

# After
defp message_type_matches?(%{type: type}, filter), do: type == filter
defp message_type_matches?(_, _), do: false
```

The special cases for `:tool_use`, `:text_delta`, `:thinking_delta`, and `:system` (which
match on content rather than top-level type) are preserved as they are today — they come
before the general clause.

## Changes Required

1. **`lib/claude_code/cli/parser.ex`** — wrap all three `@*_parsers` attributes with
   `Map.merge/2` + `Application.compile_env/3`.

2. **`lib/claude_code/stream.ex`** — replace struct-based clauses in `message_type_matches?/2`
   with `%{type: type}` field match. Preserve special-case clauses for `:tool_use`,
   `:text_delta`, `:thinking_delta`, and `:system`.

3. **`test/claude_code/cli/parser_test.exs`** — add tests for each registry:
   - override an existing type
   - add a new unknown type that was previously skipped
   - verify default behaviour unchanged when no config set

4. **`test/claude_code/stream_test.exs`** — verify `filter_type` works for a user struct
   with a `:type` field.

5. **Module doc** — add an "Extending the parser" section to `CLI.Parser` `@moduledoc`
   documenting the three config keys and the parser function contract.

## Non-goals

- Runtime (per-session or per-query) parser swapping — not needed, adds complexity
- A behaviour/callback interface — overkill given compile-env covers all three cases
- Validating user-supplied parsers at compile time — trust the user, errors surface at runtime
- Fixing `message?/1` / `content?/1` — unused internally, not worth the complexity
