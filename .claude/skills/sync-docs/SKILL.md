---
name: sync-docs
description: This skill should be used when the user asks to "sync docs", "update guides", "check docs against official", "refresh documentation", "compare guides to official docs", "update docs from upstream", or mentions syncing the SDK documentation guides with the official Claude Agent SDK documentation.
version: 1.0.0
---

# Sync Documentation Guides

Synchronize the Elixir SDK documentation guides in `docs/guides/` with the official Claude Agent SDK documentation.

## Overview

Each guide in `docs/guides/` mirrors an official Agent SDK documentation page. The guides show **Elixir SDK equivalents** of the official examples — never Python or TypeScript. This skill provides a systematic workflow to detect content drift and update guides when the official docs change.

## Guide Conventions

All guides follow rules defined in `docs/guides/CLAUDE.md`. Key rules:

- Use full module names in prose (e.g., `ClaudeCode.Stream.final_result/1`)
- Use `ClaudeCode.query/2` for one-off examples; reserve `ClaudeCode.start_link/1` + `ClaudeCode.stream/3` for streaming/multi-turn
- Pattern match directly in `fn` clauses
- Follow official structure closely but prioritize idiomatic Elixir/OTP
- Include Elixir-only guidance where it applies
- Mark incomplete sections with callouts

Guide titles must be concise (1-3 words) for sidebar navigation. Prefer "File Checkpointing" over "Rewind file changes with checkpointing". Do NOT adopt verbose titles from the official docs — keep titles short even if the official page uses a longer name.

Each guide starts with:

```markdown
# Concise Title

Subtitle describing the guide.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/PAGE). Examples are adapted for Elixir.
```

## Guide Inventory

Each guide maps to an official page at `https://platform.claude.com/docs/en/agent-sdk/{slug}`:

| Guide File | Official Slug |
|------------|--------------|
| `cost-tracking.md` | `cost-tracking` |
| `custom-tools.md` | `custom-tools` |
| `file-checkpointing.md` | `file-checkpointing` |
| `hooks.md` | `hooks` |
| `hosting.md` | `hosting` |
| `mcp.md` | `mcp` |
| `modifying-system-prompts.md` | `modifying-system-prompts` |
| `permissions.md` | `permissions` |
| `plugins.md` | `plugins` |
| `secure-deployment.md` | `secure-deployment` |
| `sessions.md` | `sessions` |
| `skills.md` | `skills` |
| `slash-commands.md` | `slash-commands` |
| `stop-reasons.md` | `stop-reasons` |
| `streaming-output.md` | `streaming-output` |
| `streaming-vs-single-mode.md` | `streaming-vs-single-mode` |
| `structured-outputs.md` | `structured-outputs` |
| `subagents.md` | `subagents` |
| `user-input.md` | `user-input` |

**Note:** `CLAUDE.md` is NOT a guide — it contains guide-writing rules. Do not replace it.

## Workflow

### Step 1: Fetch Official Content

For each guide (or a subset specified by the user), fetch the official page:

```
WebFetch: https://platform.claude.com/docs/en/agent-sdk/{slug}
```

Extract the semantic content: sections, headings, prose, tables, examples, and links.

### Step 2: Compare Against Local Guide

Read the corresponding local guide from `docs/guides/`. Compare:

1. **Structural differences** — New/removed/renamed sections
2. **Prose changes** — Updated descriptions, new paragraphs, changed wording
3. **New content** — Sections or subsections that don't exist locally
4. **Removed content** — Sections in local guide no longer in official (unless Elixir-specific)
5. **Link changes** — URLs that redirect to new locations
6. **Table updates** — New rows, columns, or changed values

### Step 3: Classify Changes

For each difference found, classify it:

- **Update** — Prose or structure changed in official; update local to match
- **Add** — New section in official; add Elixir-adapted version locally
- **Remove** — Section removed from official AND not Elixir-specific; remove locally
- **Keep** — Content only in local guide but is Elixir-specific (OTP patterns, LiveView examples, Elixir options); preserve it
- **Skip** — Python/TypeScript-specific content in official; do not add

### Step 4: Apply Changes

When applying changes:

- **Prose**: Mirror official wording but keep Elixir terminology (`:option_name` not `optionName`, module references not class references)
- **Code examples**: Translate to idiomatic Elixir following `docs/guides/CLAUDE.md` rules. Never copy Python/TypeScript examples directly.
- **Tables**: Match official structure, adapting values for Elixir (atoms instead of strings, Elixir types instead of Python/TypeScript types)
- **Links**: Use `platform.claude.com` URLs (final redirect destination). For cross-references between guides, use relative markdown links (`sessions.md`, `permissions.md`)
- **Elixir-specific sections**: Keep sections that provide Elixir/OTP value (e.g., LiveView integration, OTP supervision, GenServer patterns) even if not in official

### Step 5: Verify

After changes, verify:

- **Titles are concise** — 1-3 words for sidebar navigation (see conventions above)
- No Python/TypeScript code examples were introduced
- No references to non-existent modules or functions
- Internal cross-references between guides still resolve
- Guide still starts with the standard header format
- Elixir-specific sections are preserved

## Parallelization

For bulk syncs across all guides, dispatch parallel subagents — one per guide. Each agent:

1. Fetches the official page
2. Reads the local guide
3. Compares and applies changes directly
4. Reports a summary of changes made

## What NOT to Change

- `docs/guides/CLAUDE.md` — This is the guide-writing rules file, not a guide
- Elixir-specific sections that add value (OTP patterns, LiveView, supervision trees, GenServer examples)
- Elixir code examples — never replace with Python/TypeScript
- Module references using full names (e.g., `ClaudeCode.Stream.final_result/1`)

## Common Mistakes to Avoid

These are recurring issues found during past syncs. Check for them before finalizing changes.

### Code examples must use real SDK APIs

Every function, struct, and option referenced in code examples must exist in the actual SDK. Do not invent APIs based on what the official docs describe — verify against the source code.

Common errors caught previously:

- `ClaudeCode.Session.session_id/1` does not exist — use `ClaudeCode.get_session_id/1`
- `:hooks` is a session-only option — it cannot be passed to `ClaudeCode.query/2`
- `ClaudeCode.Agent` fields `description` and `prompt` are optional (only `:name` is enforced)
- `setting_sources` accepts strings (`["user", "project"]`), not atoms (`[:user, :project]`)

### Do not remove SDK features to match official docs

The official docs may not list all permission modes, options, or features that the Elixir SDK supports. Do not remove documented SDK features just because they are absent from the official guide. For example, `:delegate` and `:dont_ask` permission modes are valid even if the official guide does not list them.

### Follow the IO.puts/IO.inspect rule strictly

The guide-writing rules say: "Don't add unnecessary `IO.puts`/`IO.inspect` calls just to prove the example works." When translating official examples that use `print()` or `console.log()`, do NOT add equivalent `IO.puts`/`IO.inspect` calls. Instead:

- Use `ClaudeCode.Stream` helpers (`final_text/1`, `final_result/1`, `collect/1`) to show results
- Show return values via comments or variable bindings
- `IO.write/1` is acceptable in streaming examples where it writes text deltas as they arrive
- `Logger.info/1` is acceptable in hook/audit examples where logging is the point

### Pattern match on structs, not bare maps

Use `%ClaudeCode.Message.ResultMessage{}` instead of `%{type: :result}`. Bare map matches are imprecise and can match unintended data.

### Include event type in streaming pattern matches

When matching partial message events, always include the event type:

```elixir
# Correct — explicit event type
%{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}}

# Wrong — missing event type check
%{event: %{delta: %{type: :text_delta, text: text}}}
```

### Test examples must reference modules defined in the guide

If a guide defines `MyApp.Tools` with a `get_weather` tool, test examples must test `get_weather`, not a different tool like `add` that was never defined.

### Struct fields must match actual defstruct

Before documenting struct fields in tables, verify them against the actual module's `defstruct`. Fields like `total_cost_usd` may be top-level struct fields, not nested inside a `usage` map.

### Adapter status atoms

The session lifecycle uses `:provisioning` (not `:initializing`) as the initial adapter status.
