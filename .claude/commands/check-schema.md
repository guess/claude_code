# Check CLI Schema

Run the Claude CLI and compare the JSON output against our message struct definitions to identify schema drift.

## Reference Documentation

Fetch the official SDK schema from:
https://platform.claude.com/docs/en/agent-sdk/typescript

## Steps

1. Run the CLI with stream-json output:
```bash
echo "What is 2+2?" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null
```

2. Read the current struct definitions:

**Message types:**
- `lib/claude_code/message/result_message.ex`
- `lib/claude_code/message/system_message.ex`
- `lib/claude_code/message/assistant_message.ex`
- `lib/claude_code/message/user_message.ex`

**Content blocks:**
- `lib/claude_code/content/text_block.ex`
- `lib/claude_code/content/tool_use_block.ex`
- `lib/claude_code/content/tool_result_block.ex`
- `lib/claude_code/content/thinking_block.ex`

**Types:**
- `lib/claude_code/types.ex`

3. Compare the CLI JSON output against our struct definitions and report:
- **New fields**: JSON keys from CLI that we don't have in our structs
- **Missing fields**: Struct fields that aren't in the CLI output (may be optional)
- **Type mismatches**: Fields where the value type differs from what we expect
- **Naming differences**: camelCase vs snake_case inconsistencies

4. For each new field found, suggest:
- The snake_case atom key for the struct field (e.g., `"inputTokens"` -> `:input_tokens`)
- Whether to add it to the struct or ignore it
- Any transform function needed (e.g., for nested objects, enums, etc.)
