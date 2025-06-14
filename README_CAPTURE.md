# Capturing Claude CLI Output

This directory contains scripts to capture real Claude CLI JSON output for Phase 2 implementation.

## Why These Scripts?

The Claude CLI waits for stdin input, which causes it to hang when run directly. These scripts solve that by:
1. Piping input via `echo` to provide the query
2. Using `--no-prompt` to prevent interactive mode
3. Capturing all JSON output types (system, assistant, tool_use, result)

## Available Scripts

### 1. Elixir Script: `capture_cli_output.exs`

Full-featured capture with mock support:

```bash
# Capture real CLI output (requires ANTHROPIC_API_KEY)
./capture_cli_output.exs

# Create mock fixtures (no API key needed)
./capture_cli_output.exs --mock
```

### 2. Shell Script: `capture_cli_direct.sh`

Simple bash script for direct capture:

```bash
# Requires ANTHROPIC_API_KEY to be set
./capture_cli_direct.sh
```

### 3. Manual Capture

Run individual commands:

```bash
echo "Your query here" | claude --output-format stream-json --verbose --print --no-prompt > output.json
```

## Output Location

All captured outputs are saved to: `test/fixtures/cli_messages/`

## Formatting Output

The CLI outputs newline-delimited JSON. To view it nicely:

```bash
# View raw
cat test/fixtures/cli_messages/simple_hello.json

# Pretty print each JSON object
cat test/fixtures/cli_messages/simple_hello.json | jq -s .
```

## What We're Capturing

1. **Simple text responses** - Basic Q&A without tools
2. **Math calculations** - Computational responses  
3. **Tool use requests** - Commands that trigger file operations
4. **Error cases** - How errors are reported
5. **Multi-step operations** - Complex workflows with multiple tools

## Next Steps

After capturing:
1. Analyze the JSON structure of each message type
2. Identify all content block types
3. Document the schema for each type
4. Use these as test fixtures for Phase 2 implementation