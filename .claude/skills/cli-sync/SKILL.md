---
name: cli-sync
description: This skill should be used when the user asks to "check CLI schema", "sync CLI version", "check for new CLI options", "update bundled CLI", "compare SDK structs", "check schema drift", "align message structs", "verify CLI compatibility", "check control protocol", or mentions CLI compatibility, schema alignment, or wants to ensure the SDK matches the current Claude CLI. Consolidates schema checking, options validation, control protocol coverage, and version management into a single workflow.
version: 2.0.0
---

# CLI Sync

Synchronize the ClaudeCode Elixir SDK with the Claude CLI to detect schema changes, new options, control protocol drift, and update the bundled version.

## Overview

The Claude CLI evolves independently of this SDK. This skill dispatches five parallel agents to check alignment across all layers: versions, message types, content blocks, control protocol, and CLI options. Each agent has self-contained instructions in a `references/check-*.md` file.

**Canonical sources**: The TypeScript SDK (`@anthropic-ai/claude-agent-sdk`) provides the `SDKMessage` union (message types) and `SDKControl*` types (control protocol). The Anthropic API SDK (`@anthropic-ai/sdk`) provides `BetaContentBlock` types. The Python SDK (`claude-agent-sdk-python`) provides cross-reference for options and field names.

## Workflow

### Step 1: Refresh Captured Data

Run the capture script via Bash to fetch the latest CLI version, help output, and SDK type definitions:

```bash
.claude/skills/cli-sync/scripts/capture-cli-data.sh
```

This fetches `claude --version`, `claude --help`, TypeScript/Python SDK types from npm/GitHub, and Anthropic API types. Verify the script completes without errors before proceeding.

### Step 2: Dispatch Parallel Agents

Read the corresponding `references/check-*.md` file for each agent's full instructions, then dispatch all five in parallel.

| Agent | Reference File | What It Checks |
|---|---|---|
| **Versions** | `references/check-versions.md` | CLI vs bundled version alignment, SDK versions |
| **Message Types** | `references/check-message-types.md` | `SDKMessage` union vs Elixir `message/` modules |
| **Content Blocks** | `references/check-content-blocks.md` | `BetaContentBlock` union vs Elixir `content/` modules |
| **Control Protocol** | `references/check-control-protocol.md` | `SDKControl*` types vs `control.ex` and `port.ex` |
| **Options** | `references/check-options.md` | CLI flags and SDK options vs `options.ex` |

Each agent produces a structured report with coverage tables and summary counts.

### Step 3: Summarize Findings

Collect all five agent reports into a unified summary:

1. **Version alignment** -- synced or out of sync, SDK versions for reference
2. **Message type coverage** -- table with status per SDKMessage type
3. **Content block coverage** -- table with status per BetaContentBlock type + deltas
4. **Control protocol coverage** -- four tables (outbound, inbound, responses, accessors)
5. **Options coverage** -- table with status per CLI flag

Recommend next steps for any gaps found.

### Step 4: Implement Changes

For each change identified, consult the appropriate reference file for patterns:

| Change Type | Pattern Reference | Test File |
|---|---|---|
| New struct fields | `references/type-mapping.md` | `test/claude_code/message/<type>_test.exs` or `content/` |
| New CLI options | `references/cli-flags.md` | `test/claude_code/options_test.exs`, `cli/command_test.exs` |
| New control requests | `references/type-mapping.md` | `test/claude_code/cli/control_test.exs` |
| Version update | Update `@default_cli_version` in `installer.ex` | -- |

When adding new message or content types, also add a factory function in `lib/claude_code/test/factory.ex` and update `lib/claude_code/test.ex` if the type needs a user-facing test helper.

When adding new options, prefer Elixir-native syntax: atoms for enumerations, tagged tuples for variants with data, preprocessing in `command.ex` over direct mapping.

### Step 5: Update Reference Files

After implementing changes, update the data reference files to reflect the new state:

- **`references/type-mapping.md`** -- Add new rows to the appropriate table (message types, content blocks, control protocol, or other structs)
- **`references/cli-flags.md`** -- Add new flag mappings to the implemented flags table

### Step 6: Verify

```bash
mix quality    # Compile, format, credo, dialyzer
mix test       # All tests pass
```

After verification, update documentation:

1. **CLAUDE.md** -- If new options or message types added
2. **CHANGELOG.md** -- Document schema alignment changes
3. **Module docs** -- Update option descriptions as needed

## Additional Resources

### Scripts

- **`scripts/capture-cli-data.sh`** -- Main capture script (CLI version, help output, SDK type definitions)
- **`scripts/compare-versions.sh`** -- Quick version comparison

### SDK Documentation

For additional context via WebFetch:

- **TypeScript SDK**: https://platform.claude.com/docs/en/agent-sdk/typescript#options
- **Python SDK**: https://platform.claude.com/docs/en/agent-sdk/python#claude-agent-options
- **CLI Changelog**: https://docs.anthropic.com/en/docs/claude-code/changelog
