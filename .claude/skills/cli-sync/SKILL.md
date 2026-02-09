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

Run multiple test scenarios to capture different message types. Each scenario targets specific structs. The `-p` flag enables non-interactive (print) mode.

**Scenario A: Basic query** (triggers: system_message/init, assistant_message, result_message/success, text_block)
```bash
echo "What is 2+2?" | claude --output-format stream-json --verbose --max-turns 1 -p 2>/dev/null
```

**Scenario B: Partial streaming** (triggers: partial_assistant_message/stream_event)
```bash
echo "Count from 1 to 5" | claude --output-format stream-json --verbose --include-partial-messages --max-turns 1 -p 2>/dev/null
```

**Scenario C: Tool use** (triggers: tool_use_block, tool_result_block, user_message)
```bash
echo "Read the first 3 lines of mix.exs" | claude --output-format stream-json --verbose --max-turns 1 -p 2>/dev/null
```

**Scenario D: Error result - max turns** (triggers: result_message/error_max_turns)
```bash
echo "Create a file called /tmp/test_sync.txt with hello world, then read it back" | claude --output-format stream-json --verbose --max-turns 1 -p 2>/dev/null
```
This should hit the turn limit mid-task and produce a result with `"subtype": "error_max_turns"`.

**Scenario E: Hook messages** (triggers: system_message/hook_started, system_message/hook_response)

If the project has hooks configured (e.g., SessionStart hooks), Scenario A will already emit these. Check the output for `"subtype": "hook_started"` and `"subtype": "hook_response"` messages. If no hooks are configured, skip this - but still ensure the parser handles unknown system subtypes gracefully.

**Scenario F: Extended thinking** (triggers: thinking_block)
```bash
echo "Think step by step about why 17 is prime" | claude --output-format stream-json --verbose --max-turns 1 --model claude-opus-4-6 -p 2>/dev/null
```
Note: Extended thinking availability depends on model and account configuration. If thinking blocks appear, compare against `thinking_block.ex`. The block has `type`, `thinking`, and `signature` fields.

**Exceptional cases** (rely on SDK docs, not live testing):
- `compact_boundary_message` - Only during context compaction in long conversations. Cannot be reliably triggered in a single query. Check the TypeScript SDK `SDKCompactBoundaryMessage` type for the expected shape: `type: "system"`, `subtype: "compact_boundary"`, `compact_metadata: {trigger, pre_tokens}`.
- `result_message/error_max_budget_usd` - Requires a budget to be exceeded. Check SDK docs for the `error_max_budget_usd` and `error_max_structured_output_retries` subtypes.

#### Coverage Checklist

After running scenarios, verify you have captured output covering:

- [ ] `SystemMessage` (subtype: init) - Scenario A
- [ ] `SystemMessage` (subtype: hook_started) - Scenario E (if hooks configured)
- [ ] `SystemMessage` (subtype: hook_response) - Scenario E (if hooks configured)
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

Check official SDK documentation for type definitions and options. Note that CLI output is the authoritative source - SDK docs may lag behind.

**TypeScript SDK Options**: https://platform.claude.com/docs/en/agent-sdk/typescript#options
**Python SDK Options**: https://platform.claude.com/docs/en/agent-sdk/python#claude-agent-options
**Python SDK Source** (opts→CLI flag mapping): https://github.com/anthropics/claude-agent-sdk-python/blob/main/src/claude_agent_sdk/_internal/transport/subprocess_cli.py

WebFetch these pages to compare options and types against our SDK. The Python source is especially useful since docs can lag behind - the `subprocess_cli.py` file shows exactly which options are converted to CLI flags.

- **Options comparison**: Check which CLI flags the official SDKs expose as options. If a CLI flag is NOT present in either official SDK, it likely doesn't make sense for our SDK (e.g., `--chrome`, `--ide`, `--replay-user-messages` are CLI-only).
- **Message type definitions**: Compare `SDKMessage` union types against our message structs.
- **Content block schemas**: Compare content block types against our content modules.
- **New option descriptions**: Check for options added in official SDKs that we should also support.

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

- **`scripts/run-test-query.sh`** - Run test query and save JSON output
- **`scripts/compare-versions.sh`** - Compare installed vs bundled versions (run from project root)

## Updating Documentation

After syncing, update:

1. **CLAUDE.md** - If new options or message types added
2. **CHANGELOG.md** - Document schema alignment changes
3. **Module docs** - Update option descriptions in Options module
