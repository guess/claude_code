# CLI Sync

Synchronize the SDK with the current Claude CLI version.

## Task

Dispatch three parallel agents to perform independent checks simultaneously:

### Agent 1: Version Check
Compare installed CLI version vs bundled version:
- Run `claude --version` to get installed version
- Read `lib/claude_code/installer.ex` and find `@default_cli_version`
- Report if versions match or differ

### Agent 2: Schema Check
Compare CLI JSON output against message/content structs by running multiple test scenarios:

**Scenario A: Basic query** (triggers: system, assistant, result, text_block)
```bash
echo "What is 2+2?" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null
```

**Scenario B: Partial streaming** (triggers: partial_assistant)
```bash
echo "Count from 1 to 5" | claude --output-format stream-json --verbose --include-partial-messages --max-turns 1 2>/dev/null
```

**Scenario C: Tool use** (triggers: tool_use_block, tool_result_block, user_message)
```bash
echo "Read the first 3 lines of mix.exs" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null
```

Then:
- Read all files in `lib/claude_code/message/` and `lib/claude_code/content/`
- Compare JSON keys from each scenario against struct fields
- Report new fields, missing fields, or type mismatches

**Note**: Exceptional cases (compact_boundary, thinking_block) rely on SDK docs rather than live testing.

### Agent 3: Options Check
Compare CLI help against Options module:
- Run `claude --help`
- Read `lib/claude_code/options.ex`
- Compare CLI flags against `@session_opts_schema` and `convert_option_to_cli_flag/2` clauses
- Report new flags not in our schema or deprecated flags we still support
- **Ignore**: `--verbose`, `--output-format`, `--input-format` (always enabled by SDK in cli.ex, not user-configurable)

## After Parallel Checks Complete

1. Collect results from all three agents
2. If version differs, update `@default_cli_version` in `lib/claude_code/installer.ex`
3. Summarize all findings and recommend next steps

Use the cli-sync skill for detailed patterns and reference documentation when implementing fixes.
