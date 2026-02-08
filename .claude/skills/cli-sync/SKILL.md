---
name: CLI Sync
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

## Quick Start

For a full sync, execute these steps in order:

1. Check current versions
2. Run test query to capture live schema
3. Compare against struct definitions
4. Check CLI help for new options
5. Update installer version if needed

## Workflow

### Step 1: Version Check

Determine installed CLI version and compare to bundled version.

```bash
# Get installed CLI version
claude --version

# Check bundled version in installer
grep -E "@default_cli_version|cli_version:" lib/claude_code/installer.ex
```

### Step 2: Schema Comparison

Run a test query with `--verbose` to capture all message types.

```bash
# Run test query capturing full JSON output
echo "What is 2+2?" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null
```

Parse the output and compare against struct definitions in:

**Message Types** (in `lib/claude_code/message/`):
- `system_message.ex` - Init messages with session_id, tools, model, etc.
- `assistant_message.ex` - Messages with nested `message.content` blocks
- `user_message.ex` - User input with tool results
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

Compare CLI help output against the Options module.

```bash
# Get CLI help
claude --help
```

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

Check official SDK documentation for type definitions. Note that CLI output is the authoritative source - SDK docs may lag behind.

**TypeScript SDK**: https://platform.claude.com/docs/en/agent-sdk/typescript
**Python SDK**: https://platform.claude.com/docs/en/agent-sdk/python

WebFetch can retrieve these pages to check for:
- Message type definitions
- Content block schemas
- New option descriptions

### Step 5: Update Bundled Version

After confirming compatibility, update the bundled CLI version.

Edit `lib/claude_code/installer.ex`:

```elixir
# Update @default_cli_version to match installed CLI
@default_cli_version "X.Y.Z"
```

Also update the moduledoc comment showing the version:

```elixir
cli_version: "X.Y.Z",           # Version to install (default: SDK's tested version)
```

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

Before making changes, check the CLI changelog for breaking changes:

```bash
# Check recent CLI releases
gh release list --repo anthropics/anthropic-quickstarts --limit 10
```

Or check the changelog documentation if available at:
- https://docs.anthropic.com/en/docs/claude-code/changelog

## Common Issues

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

- **`scripts/run-test-query.sh`** - Run test query and save JSON output
- **`scripts/compare-versions.sh`** - Compare installed vs bundled versions (run from project root)

## Updating Documentation

After syncing, update:

1. **CLAUDE.md** - If new options or message types added
2. **CHANGELOG.md** - Document schema alignment changes
3. **Module docs** - Update option descriptions in Options module
