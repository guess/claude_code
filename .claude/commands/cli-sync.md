---
description: Synchronize SDK with current Claude CLI version
---

# CLI Sync

Synchronize the SDK with the current Claude CLI by analyzing captured CLI data.

## Step 1: Check for captured data

Check if `.claude/skills/cli-sync/captured/` exists and has recent files. If it does, skip to Step 3. If it doesn't exist or is stale, proceed to Step 2.

## Step 2: Ask user to run capture script

Tell the user:

> Please run the capture script from the project root, then confirm when done:
>
> ```bash
> .claude/skills/cli-sync/scripts/capture-cli-data.sh
> ```
>
> This captures CLI version, help output, test scenarios (schema samples), and Python SDK sources. It takes about 30 seconds.

Use AskUserQuestion to ask "Have you run the capture script?" with options:
- "Yes, it completed successfully"
- "It failed or had errors"

If they report failure, help troubleshoot based on which files are missing in `captured/`. If they confirm success, proceed.

## Step 3: Analyze captured data

Read ALL files in `.claude/skills/cli-sync/captured/` and dispatch three parallel agents:

### Agent 1: Version Check
- Read `captured/cli-version.txt` and `captured/bundled-version.txt`
- Read `lib/claude_code/adapter/local/installer.ex` to find `@default_cli_version`
- Report if versions match or differ

### Agent 2: Schema Check
- Read all scenario JSONL files (`scenario-a-basic.jsonl` through `scenario-f-thinking.jsonl`)
- Read all files in `lib/claude_code/message/` and `lib/claude_code/content/`
- Read `captured/python-sdk-types.py` for canonical type definitions
- Compare JSON keys from each scenario against struct fields
- Report new fields, missing fields, or type mismatches
- Cross-reference against Python SDK types

### Agent 3: Options Check
- Read `captured/cli-help.txt`
- Read `captured/python-sdk-subprocess-cli.py` for Python SDK's `_build_command()` flag mapping
- Read `lib/claude_code/options.ex`
- Compare CLI flags against `@session_opts_schema` and `convert_option_to_cli_flag/2` clauses
- Report new flags not in our schema or deprecated flags we still support
- **Ignore**: `--verbose`, `--output-format`, `--input-format`, `--print` (always enabled by SDK)
- **Ignore CLI-only**: `--chrome`, `--no-chrome`, `--ide`, `--replay-user-messages`

## Step 4: Summarize findings

After all agents complete:

1. Collect results from all three agents
2. Present a structured summary:
   - **Version**: synced or out of sync (with update instruction)
   - **Schema drift**: new/missing/changed fields per message type
   - **Options drift**: new/missing/changed CLI flags
3. If version differs, offer to update `@default_cli_version` in `lib/claude_code/adapter/local/installer.ex`
4. Recommend next steps for any schema or options changes found

Use the cli-sync skill (`@.claude/skills/cli-sync/`) for detailed patterns and reference documentation when implementing fixes.
