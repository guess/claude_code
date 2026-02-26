---
name: cli-sync
description: This skill should be used when the user asks to "check CLI schema", "sync CLI version", "check for new CLI options", "update bundled CLI", "compare SDK structs", "check schema drift", "align message structs", "verify CLI compatibility", or mentions CLI compatibility, schema alignment, or wants to ensure the SDK matches the current Claude CLI. Consolidates schema checking, options validation, and version management into a single workflow.
version: 1.2.0
---

# CLI Sync

Synchronize the ClaudeCode Elixir SDK with the Claude CLI to detect schema changes, new options, and update the bundled version.

## Overview

The Claude CLI evolves independently of this SDK. This skill provides a systematic workflow to:

1. **Detect schema drift** - Diff TS SDK type definitions against Elixir structs for complete type coverage
2. **Find new CLI options** - Compare `--help` output and SDK sources against the Options module
3. **Cross-reference SDK docs** - Check both TypeScript and Python SDK types for canonical definitions
4. **Update bundled version** - Sync the installer to the current CLI version

**Type discovery strategy**: The TypeScript SDK (`@anthropic-ai/claude-agent-sdk`) is the canonical source for message types. Its `sdk.d.ts` exports an `SDKMessage` union listing all 20 message types. By git-tracking the captured SDK sources, version-to-version diffs automatically surface new types, removed types, and field changes.

**Python SDK**: The Python SDK (`claude-agent-sdk-python`) is a thin wrapper around the CLI — it spawns `claude` as a subprocess and communicates via streaming JSON, just like this SDK. Its `types.py` defines a subset of message types (5 types) and the options interface. It remains useful for options cross-referencing and field-level validation.

**Scenarios**: Live CLI scenarios remain useful for field-level validation (checking actual JSON keys against struct fields) but are no longer the primary method for type discovery.

## Workflow

### Step 1: Check Captured Data Freshness

Run `claude --version` via Bash to get the currently installed CLI version. Then check if `.claude/skills/cli-sync/captured/cli-version.txt` exists and read it.

**Compare the two versions:**

- If captured data doesn't exist, go to Step 2.
- If the installed CLI version is **newer** than the captured version, the data is **stale** — go to Step 2.
- If versions match, the captured data is fresh — skip to Step 3.

### Step 2: Ask User to Run Capture Script

The capture script must be run by the user because Claude cannot invoke the `claude` CLI from within a session.

Tell the user:

> The captured CLI data is stale (or missing). Your installed CLI is **{installed_version}** but the captured data is from **{captured_version}**.
>
> Please run the capture script from the project root:
>
> ```bash
> .claude/skills/cli-sync/scripts/capture-cli-data.sh
> ```
>
> This captures CLI version, help output, test scenarios (schema samples), Python SDK sources, TypeScript SDK type definitions, and SDK version tracking. It takes about 30 seconds. Let me know when it's done.

Use AskUserQuestion to ask "Have you run the capture script?" with options:
- "Yes, it completed successfully"
- "It failed or had errors"

If they report failure, help troubleshoot based on which files are missing in `captured/`.

If they confirm success, **re-read** `.claude/skills/cli-sync/captured/cli-version.txt` and verify it now matches the installed CLI version from Step 1. If it still doesn't match, tell the user and ask them to try again. Only proceed when versions match.

### Step 3: Analyze Captured Data

Read ALL files in `.claude/skills/cli-sync/captured/` and dispatch three parallel agents:

#### Agent 1: Version Check
- Read `captured/cli-version.txt` and `captured/bundled-version.txt`
- Read `lib/claude_code/adapter/local/installer.ex` to find `@default_cli_version`
- Read `captured/ts-sdk-version.txt` and `captured/py-sdk-version.txt` for SDK versions
- Report if CLI versions match or differ
- Report TypeScript SDK version and Python SDK version for reference

#### Agent 2: Schema Check (diff-based type discovery)

**Primary: TS SDK type discovery**
- Diff captured SDK types against previous git version: `git diff HEAD -- .claude/skills/cli-sync/captured/ts-sdk-types.d.ts` and `python-sdk-types.py`
- Extract the `SDKMessage` union from `captured/ts-sdk-types.d.ts` — list all member types
- Compare against Elixir implementations in `lib/claude_code/message/` and `lib/claude_code/cli/parser.ex`
- Categorize each TS SDK type as: **fully implemented** (dedicated struct), **handled by catch-all** (e.g. system subtypes in SystemMessage), or **missing**

**Secondary: Field-level validation via scenarios**
- Read all scenario JSONL files (`scenario-a-basic.jsonl` through `scenario-f-thinking.jsonl`)
- Read all files in `lib/claude_code/message/` and `lib/claude_code/content/`
- Compare JSON keys from each scenario against struct fields
- Report new fields, missing fields, or type mismatches
- Cross-reference against `captured/python-sdk-types.py` for Python SDK type definitions

**Output: Coverage table**
- Produce a table with columns: TS SDK Type | Wire Type (`type` field value) | Elixir Module | Status
- Status values: Implemented, Catch-all, Missing
- See `references/struct-definitions.md` for complete field mappings and coverage checklist

#### Agent 3: Options Check
- Read `captured/cli-help.txt`
- Read `captured/python-sdk-subprocess-cli.py` for Python SDK's `_build_command()` flag mapping
- Read `captured/ts-sdk-types.d.ts` for the TypeScript SDK Options type definition
- Read `lib/claude_code/options.ex`
- Compare CLI flags against `@session_opts_schema` and `convert_option_to_cli_flag/2` clauses
- Cross-reference options from both TS and Python SDKs
- Report new flags not in our schema or deprecated flags we still support
- **Ignore SDK-internal**: `--verbose`, `--output-format`, `--input-format`, `--print` (always enabled)
- **Ignore CLI-only**: `--chrome`, `--no-chrome`, `--ide`, `--replay-user-messages`
- See `references/cli-flags.md` for flag mappings and patterns

### Step 4: Summarize Findings

After all agents complete:

1. Collect results from all three agents
2. Present a structured summary:
   - **Version**: CLI synced or out of sync (with update instruction); TS/Python SDK versions
   - **Type coverage**: coverage table from Agent 2 (TS SDK Type | Wire Type | Elixir Module | Status)
   - **Schema drift**: new/missing/changed fields per message type (from scenario analysis)
   - **Options drift**: new/missing/changed CLI flags
3. If version differs, offer to update `@default_cli_version` in `lib/claude_code/adapter/local/installer.ex`
4. Recommend next steps for any schema or options changes found

### Step 5: Implement Changes

For each change identified:

**New struct fields** — Add to the appropriate struct module, update the `parse` function to extract the field from JSON (camelCase to snake_case), default to `nil` when absent. See `references/struct-definitions.md` for patterns.

**New CLI options** — Add to `@session_opts_schema` in `options.ex` with NimbleOptions type, add `convert_option_to_cli_flag/2` clause in `command.ex`. Consider Elixir-native syntax (atoms, tagged tuples) over dict-style APIs. See "Elixir-Native API Design" below and `references/cli-flags.md` for patterns.

**Version update** — Update `@default_cli_version` in `lib/claude_code/adapter/local/installer.ex` (the single source of truth).

### Step 6: Write Tests

Write tests for every new field and option:

| Change Type | Test File |
|-------------|-----------|
| New option in `options.ex` | `test/claude_code/options_test.exs` |
| New CLI flag in `command.ex` | `test/claude_code/cli/command_test.exs` |
| New field in a message struct | `test/claude_code/message/<type>_test.exs` |
| New field in a content block | `test/claude_code/content/<type>_test.exs` |

### Step 7: Verify

```bash
mix quality    # Compile, format, credo, dialyzer
mix test       # All tests pass
```

## Elixir-Native API Design

When adding new options, consider idiomatic Elixir representations instead of blindly mirroring Python/TypeScript APIs.

**Atoms for enumerations** — Use `:adaptive`, `:disabled` instead of `"adaptive"`, `"disabled"`.

**Tagged tuples for variants with data** — Use `{:tag, data}` instead of maps with a type field.

**Preprocessing over direct mapping** — Complex options can be preprocessed into simpler CLI flags via `command.ex`.

**Example**: The `:thinking` option uses `thinking: :adaptive` and `thinking: {:enabled, budget_tokens: 16_000}` instead of Python's `thinking={"type": "enabled", "budget_tokens": 16000}`.

Use Elixir-native syntax when an option has a small fixed set of modes or uses a `type` discriminator. Keep simple scalars, lists of strings, and opaque maps as-is.

## Common Issues

**camelCase vs snake_case** — CLI uses camelCase (`"inputTokens"`), Elixir uses snake_case (`:input_tokens`).

**Nested message structure** — Access content via `message.message.content`, not `message.content`. Outer `message` is our struct, inner `message` is from CLI JSON.

**Result vs assistant content** — Final response text comes from `ResultMessage.result`, not `AssistantMessage`.

## Additional Resources

### Reference Files

- **`references/struct-definitions.md`** - Complete field mappings, coverage checklist, adding new fields
- **`references/cli-flags.md`** - All flag mappings, patterns for adding new flags

### Scripts

- **`scripts/capture-cli-data.sh`** - Main capture script (collects all data for sync analysis)
- **`scripts/run-test-query.sh`** - Run individual test scenarios (used internally by capture script)
- **`scripts/compare-versions.sh`** - Compare installed vs bundled versions

### SDK Documentation Pages

For additional context, check via WebFetch:

- **Python SDK Options**: https://platform.claude.com/docs/en/agent-sdk/python#claude-agent-options
- **TypeScript SDK Options**: https://platform.claude.com/docs/en/agent-sdk/typescript#options

### Changelog

Before making changes, check the CLI changelog for breaking changes:

- https://docs.anthropic.com/en/docs/claude-code/changelog

## Updating Documentation

After syncing, update:

1. **CLAUDE.md** - If new options or message types added
2. **CHANGELOG.md** - Document schema alignment changes
3. **Module docs** - Update option descriptions in Options module
