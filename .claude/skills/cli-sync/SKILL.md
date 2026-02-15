---
name: cli-sync
description: This skill should be used when the user asks to "check CLI schema", "sync CLI version", "check for new CLI options", "update bundled CLI", "compare SDK structs", "check schema drift", "align message structs", "verify CLI compatibility", or mentions CLI compatibility, schema alignment, or wants to ensure the SDK matches the current Claude CLI. Consolidates schema checking, options validation, and version management into a single workflow.
version: 1.0.0
---

# CLI Sync

Synchronize the ClaudeCode Elixir SDK with the Claude CLI to detect schema changes, new options, and update the bundled version.

## Overview

The Claude CLI evolves independently of this SDK. This skill provides a systematic workflow to:

1. **Detect schema drift** - Compare CLI JSON output against our message/content structs
2. **Find new CLI options** - Compare `--help` output against our Options module
3. **Check SDK documentation** - Reference TypeScript/Python SDK docs for type information
4. **Update bundled version** - Sync the installer to the current CLI version

**Important**: The Python SDK (`claude-agent-sdk-python`) is a thin wrapper around the CLI — it spawns `claude` as a subprocess and communicates via streaming JSON, just like our SDK. This makes it the closest reference for what is possible and appropriate to implement. Its `types.py` defines the canonical message types, content blocks, and options that a CLI-wrapping SDK should support. When in doubt about whether a field or option belongs in our SDK, check the Python SDK first.

## Quick Start

Since Claude Code cannot invoke the `claude` CLI directly, a capture script collects all needed data for you to provide to Claude.

**Step 1**: Run the capture script from the project root:

```bash
.claude/skills/cli-sync/scripts/capture-cli-data.sh
```

This saves all data to `.claude/skills/cli-sync/captured/`.

**Step 2**: Tell Claude to analyze the captured data:

> "Read .claude/skills/cli-sync/captured/ and perform a CLI sync analysis"

Claude will then read the captured files and perform steps 2-6 below.

## What the Capture Script Collects

The script (`scripts/capture-cli-data.sh`) runs these operations and saves results:

| File | What it captures |
|------|-----------------|
| `cli-version.txt` | `claude --version` output |
| `cli-help.txt` | `claude --help` output |
| `bundled-version.txt` | Current `@default_cli_version` from installer.ex |
| `scenario-a-basic.jsonl` | Basic query (system, assistant, result, text_block) |
| `scenario-b-partial.jsonl` | Partial streaming (partial_assistant_message) |
| `scenario-c-tool.jsonl` | Tool use (tool_use_block, tool_result_block, user_message) |
| `scenario-d-error.jsonl` | Error max turns (result with error_max_turns) |
| `scenario-f-thinking.jsonl` | Extended thinking (thinking_block) |
| `python-sdk-types.py` | Python SDK types.py (via `gh`) |
| `python-sdk-subprocess-cli.py` | Python SDK subprocess_cli.py (via `gh`) |

## Workflow

### Step 1: Run Capture Script

```bash
.claude/skills/cli-sync/scripts/capture-cli-data.sh
```

The script requires `claude` and `gh` CLIs in PATH. Missing tools are noted in the output files.

### Step 2: Schema Comparison

Read the scenario JSONL files from `captured/` and compare against struct definitions.

Each scenario targets specific message/content types:

- **Scenario A** (`scenario-a-basic.jsonl`): system_message/init, assistant_message, result_message/success, text_block
- **Scenario B** (`scenario-b-partial.jsonl`): partial_assistant_message/stream_event
- **Scenario C** (`scenario-c-tool.jsonl`): tool_use_block, tool_result_block, user_message
- **Scenario D** (`scenario-d-error.jsonl`): result_message/error_max_turns
- **Scenario F** (`scenario-f-thinking.jsonl`): thinking_block (if available)

**Exceptional cases** (rely on SDK docs in `python-sdk-types.py`, not live testing):

- `compact_boundary_message` - Only during context compaction in long conversations.
- `result_message/error_max_budget_usd` - Requires a budget to be exceeded.

#### Coverage Checklist

After reading scenario files, verify coverage of:

- [ ] `SystemMessage` (subtype: init) - Scenario A
- [ ] `AssistantMessage` with nested message.content - Scenario A
- [ ] `UserMessage` with tool results - Scenario C
- [ ] `ResultMessage` (subtype: success) - Scenario A
- [ ] `ResultMessage` (subtype: error_max_turns) - Scenario D
- [ ] `PartialAssistantMessage` (stream_event) - Scenario B
- [ ] `TextBlock` - Scenario A
- [ ] `ToolUseBlock` - Scenario C
- [ ] `ToolResultBlock` - Scenario C
- [ ] `ThinkingBlock` - Scenario F (if available)
- [ ] `CompactBoundaryMessage` - SDK docs only

Parse each JSONL file (one JSON object per line) and compare against struct definitions in:

**Message Types** (in `lib/claude_code/message/`):

- `system_message.ex` - All system subtypes: init (with dedicated fields), hook_started, hook_response, etc. (non-init use `data` map)
- `assistant_message.ex` - Messages with nested `message.content` blocks, optional `error` field
- `user_message.ex` - User input with tool results, optional `tool_use_result` metadata
- `result_message.ex` - Final response with result text and is_error flag
- `partial_assistant_message.ex` - Streaming partial content
- `compact_boundary_message.ex` - Context compaction boundaries

**Content Blocks** (in `lib/claude_code/content/`):

- `text_block.ex` - Text content with type: "text"
- `tool_use_block.ex` - Tool invocations with id, name, input
- `tool_result_block.ex` - Tool outputs with tool_use_id, content, is_error
- `thinking_block.ex` - Extended thinking with signature

For each message type in the CLI output:

1. Identify the message type from `"type"` field
2. Compare JSON keys against struct fields
3. Report new fields, missing fields, and type mismatches
4. Suggest snake_case atom names for new fields

See `references/struct-definitions.md` for complete field mappings.

### Step 3: Options Comparison

Read `captured/cli-help.txt` and compare against the Options module.

Options module comparison points in `lib/claude_code/options.ex`:

1. Check `@session_opts_schema` for option definitions
2. Check `convert_option_to_cli_flag/2` clauses for CLI mappings
3. Look for new flags in `--help` not in our schema
4. Check for deprecated flags we still support

For each new flag found, suggest:

- The `:snake_case_atom` option name
- NimbleOptions type definition
- `convert_option_to_cli_flag/2` clause

### Step 4: SDK Documentation Reference

Read the captured Python SDK source files for type definitions and options. Note that CLI output is the authoritative source - SDK docs may lag behind.

#### Captured Python SDK Files

The capture script fetches these via `gh` and saves them locally:

- **`captured/python-sdk-subprocess-cli.py`** - CLI flag mapping (`_build_command()` method). THE most useful file for options sync.
- **`captured/python-sdk-types.py`** - Canonical message/content type definitions. Maps directly to what our structs should support.

If the capture script failed to fetch these (check file contents), you can ask the user to run:

```bash
gh api repos/anthropics/claude-agent-sdk-python/contents/src/claude_agent_sdk/types.py --jq '.content' | base64 -d > .claude/skills/cli-sync/captured/python-sdk-types.py
gh api repos/anthropics/claude-agent-sdk-python/contents/src/claude_agent_sdk/_internal/transport/subprocess_cli.py --jq '.content' | base64 -d > .claude/skills/cli-sync/captured/python-sdk-subprocess-cli.py
```

#### Key Types to Compare in `python-sdk-types.py`

- `UserMessage` — has `tool_use_result: dict[str, Any] | None`
- `AssistantMessage` — has `error: AssistantMessageError | None`
- `SystemMessage` — generic `subtype: str` + `data: dict[str, Any]` (handles all subtypes)
- `ResultMessage`, `StreamEvent`, content blocks (`TextBlock`, `ThinkingBlock`, `ToolUseBlock`, `ToolResultBlock`)
- `ClaudeAgentOptions` — all available SDK options

#### SDK Documentation Pages

For additional context, these doc pages can be checked via WebFetch:

- **TypeScript SDK Options**: https://platform.claude.com/docs/en/agent-sdk/typescript#options
- **Python SDK Options**: https://platform.claude.com/docs/en/agent-sdk/python#claude-agent-options

#### What to Compare

- **Options comparison**: Check which CLI flags the official SDKs expose as options. If a CLI flag is NOT present in either official SDK, it likely doesn't make sense for our SDK (e.g., `--chrome`, `--ide`, `--replay-user-messages` are CLI-only).
- **Message type definitions**: Compare `SDKMessage` union types against our message structs.
- **Content block schemas**: Compare content block types against our content modules.
- **New option descriptions**: Check for options added in official SDKs that we should also support.

### Step 5: Update Bundled Version

Compare `captured/cli-version.txt` against `captured/bundled-version.txt`. If they differ, update the bundled CLI version.

The **single source of truth** for the CLI version is `@default_cli_version` in `lib/claude_code/installer.ex`. This is the only place that needs updating:

```elixir
# Update @default_cli_version to match installed CLI
@default_cli_version "X.Y.Z"
```

No other files should hardcode the CLI version. Docs, comments, and config examples use generic placeholders like `"x.y.z"`.

### Step 6: Verify and Test

After making changes:

```bash
# Run quality checks
mix quality

# Run tests
mix test

# Verify struct parsing with updated code
mix test test/claude_code/message_test.exs
```

## Pattern References

For detailed patterns on adding new fields and options:

- **Schema patterns** - See `references/struct-definitions.md` for field mappings, adding new fields, handling nested structures, and optional field patterns
- **Options patterns** - See `references/cli-flags.md` for boolean flags, value flags, list flags, and CLI conversion clauses

## Changelog Checking

Before making changes, check the CLI changelog for breaking changes. Ask the user to run:

```bash
gh release list --repo anthropics/anthropic-quickstarts --limit 10
```

Or check the changelog documentation via WebFetch:

- https://docs.anthropic.com/en/docs/claude-code/changelog

## Common Issues

### Flags to Ignore

When comparing `--help` output, ignore these flags that appear in CLI help but should NOT be added to `options.ex`:

**SDK-internal flags** (always set by the SDK automatically):

- `--verbose` - Already always enabled by SDK in `cli.ex` (required for streaming)
- `--output-format` - Already always set to `stream-json` by SDK
- `--input-format` - Already always set to `stream-json` by SDK
- `--print` / `-p` - Internal print mode flag

**CLI-only flags** (not in either official SDK, not relevant for programmatic use):

- `--chrome` / `--no-chrome` - Browser integration for interactive terminal
- `--ide` - IDE auto-connect for interactive terminal
- `--replay-user-messages` - Internal streaming protocol flag (handled transparently by SDKs)

Cross-reference against official SDK options pages to confirm whether new flags belong in the SDK.

### camelCase vs snake_case

CLI uses camelCase, Elixir uses snake_case:

- `"inputTokens"` -> `:input_tokens`
- `"isError"` -> `:is_error`
- `"toolUseId"` -> `:tool_use_id`

### Nested Message Structure

Assistant and User messages have nested structure:

- Access content via `message.message.content`, not `message.content`
- The outer `message` is our struct, inner `message` is from CLI JSON

### Result vs Assistant Content

Final response text comes from ResultMessage, not AssistantMessage:

- Use `result.result` for the final answer
- AssistantMessage contains intermediate tool use and thinking

## Additional Resources

### Reference Files

- **`references/struct-definitions.md`** - Complete field mappings for all structs
- **`references/cli-flags.md`** - CLI flag documentation and mappings

### Scripts

Ensure scripts are executable before first use: `chmod +x scripts/*.sh`

- **`scripts/capture-cli-data.sh`** - Main capture script: collects all data needed for sync analysis
- **`scripts/run-test-query.sh`** - Run individual test scenarios (used internally by capture script)
- **`scripts/compare-versions.sh`** - Compare installed vs bundled versions (run from project root)

## Updating Documentation

After syncing, update:

1. **CLAUDE.md** - If new options or message types added
2. **CHANGELOG.md** - Document schema alignment changes
3. **Module docs** - Update option descriptions in Options module
