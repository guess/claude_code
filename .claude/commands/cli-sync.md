---
description: Synchronize SDK with current Claude CLI version
---

# CLI Sync

Synchronize the SDK with the current Claude CLI by analyzing captured CLI data.

## Step 1: Check captured data freshness

Run `claude --version` via Bash to get the currently installed CLI version. Then check if `.claude/skills/cli-sync/captured/cli-version.txt` exists and read it.

**Compare the two versions:**

- If captured data doesn't exist, go to Step 2.
- If the installed CLI version is **newer** than the captured version, the data is **stale** — go to Step 2.
- If versions match, the captured data is fresh — skip to Step 3.

## Step 2: Ask user to run capture script

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
> This captures CLI version, help output, test scenarios (schema samples), and Python SDK sources. It takes about 30 seconds. Let me know when it's done.

Use AskUserQuestion to ask "Have you run the capture script?" with options:
- "Yes, it completed successfully"
- "It failed or had errors"

If they report failure, help troubleshoot based on which files are missing in `captured/`.

If they confirm success, **re-read** `.claude/skills/cli-sync/captured/cli-version.txt` and verify it now matches the installed CLI version from Step 1. If it still doesn't match, tell the user and ask them to try again. Only proceed when versions match.

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
