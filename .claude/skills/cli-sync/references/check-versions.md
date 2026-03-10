# Check Versions

Self-contained instructions for a parallel agent that checks version alignment across the CLI, bundled installer, and upstream SDKs.

## Purpose

Check if CLI version, bundled version, and SDK versions are aligned. Report match/mismatch status and surface the exact line to update when out of sync.

## Files to Read

All paths are relative to the project root.

| File | Contents |
|---|---|
| `.claude/skills/cli-sync/captured/cli-version.txt` | Installed CLI version (output of `claude --version`) |
| `.claude/skills/cli-sync/captured/ts-sdk-version.txt` | TypeScript SDK (`@anthropic-ai/claude-agent-sdk`) version |
| `.claude/skills/cli-sync/captured/py-sdk-version.txt` | Python SDK (`claude-agent-sdk-python`) version |
| `.claude/skills/cli-sync/captured/anthropic-sdk-version.txt` | Anthropic API SDK version |
| `lib/claude_code/adapter/port/installer.ex` | Source of truth for `@default_cli_version` |

## Analysis Steps

1. **Parse installed CLI version** from `cli-version.txt`. The file contains raw `claude --version` output; extract the semver string (e.g., `2.1.70`).

2. **Read `@default_cli_version`** from `installer.ex`. Search for the line matching `@default_cli_version "X.Y.Z"` and extract the version string. This is the single source of truth for version bumps.

3. **Compare installed vs bundled**. The installed CLI version (step 1) and the `@default_cli_version` (step 2) should match. If they differ, the SDK's installer is targeting a different version than what is installed locally.

4. **Read SDK versions** from `ts-sdk-version.txt`, `py-sdk-version.txt`, and `anthropic-sdk-version.txt`. These are informational — report them for cross-reference but do not compare against the CLI version (they version independently).

## Output Format

Return a structured report with the following fields:

```
Installed CLI version:   X.Y.Z
Bundled CLI version:     X.Y.Z
Match status:            synced | OUT OF SYNC
TS SDK version:          X.Y.Z
Python SDK version:      X.Y.Z
Anthropic API SDK version: X.Y.Z
```

If out of sync, additionally include:

- The exact line from `installer.ex` containing `@default_cli_version` that needs updating.
- The target version to set (the installed CLI version).
- Example: `Update @default_cli_version "2.1.70" to "2.1.75" in lib/claude_code/adapter/port/installer.ex`.

If synced, confirm no action is needed.
