#!/bin/bash
# Capture all CLI data needed for schema sync analysis.
#
# Run this script manually, then provide the output directory to Claude
# so it can read the captured data and perform the sync analysis.
#
# Usage:
#   .claude/skills/cli-sync/scripts/capture-cli-data.sh [output_dir]
#
# Default output_dir: .claude/skills/cli-sync/captured/
#
# What it captures:
#   - CLI version
#   - CLI --help output
#   - Test scenarios A-F (JSON schema samples)
#   - Python SDK types.py and subprocess_cli.py (via gh)
#
# After running, tell Claude:
#   "Read the captured CLI data in .claude/skills/cli-sync/captured/ and perform a sync analysis"

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/../captured}"

mkdir -p "$OUTPUT_DIR"

echo "=== CLI Sync Data Capture ==="
echo "Output directory: $OUTPUT_DIR"
echo ""

# --- Version Info ---
echo "[1/9] Capturing CLI version..."
if command -v claude &> /dev/null; then
    claude --version 2>/dev/null > "$OUTPUT_DIR/cli-version.txt" || echo "FAILED" > "$OUTPUT_DIR/cli-version.txt"
    echo "  Done: cli-version.txt"
else
    echo "ERROR: claude not found in PATH" > "$OUTPUT_DIR/cli-version.txt"
    echo "  WARNING: claude CLI not found"
fi

# --- Help Output ---
echo "[2/9] Capturing CLI --help..."
if command -v claude &> /dev/null; then
    claude --help 2>&1 > "$OUTPUT_DIR/cli-help.txt" || echo "FAILED" > "$OUTPUT_DIR/cli-help.txt"
    echo "  Done: cli-help.txt"
else
    echo "SKIPPED: claude not found" > "$OUTPUT_DIR/cli-help.txt"
fi

# --- Bundled Version ---
echo "[3/9] Capturing bundled version..."
INSTALLER_FILE="$PROJECT_ROOT/lib/claude_code/installer.ex"
if [ -f "$INSTALLER_FILE" ]; then
    BUNDLED=$(grep '@default_cli_version' "$INSTALLER_FILE" | head -1 | grep -o '"[^"]*"' | tr -d '"')
    echo "bundled_version=$BUNDLED" > "$OUTPUT_DIR/bundled-version.txt"
    echo "  Bundled: $BUNDLED"
else
    echo "bundled_version=NOT_FOUND" > "$OUTPUT_DIR/bundled-version.txt"
    echo "  WARNING: installer.ex not found"
fi

# --- Scenario A: Basic query ---
echo "[4/9] Scenario A: Basic query (system, assistant, result, text_block)..."
if command -v claude &> /dev/null; then
    echo "What is 2+2?" | claude --output-format stream-json --verbose --max-turns 1 -p 2>/dev/null \
        > "$OUTPUT_DIR/scenario-a-basic.jsonl" || echo '{"error":"scenario_failed"}' > "$OUTPUT_DIR/scenario-a-basic.jsonl"
    echo "  Done: scenario-a-basic.jsonl"
else
    echo '{"error":"claude_not_found"}' > "$OUTPUT_DIR/scenario-a-basic.jsonl"
fi

# --- Scenario B: Partial streaming ---
echo "[5/9] Scenario B: Partial streaming (partial_assistant_message)..."
if command -v claude &> /dev/null; then
    echo "Count from 1 to 5" | claude --output-format stream-json --verbose --include-partial-messages --max-turns 1 -p 2>/dev/null \
        > "$OUTPUT_DIR/scenario-b-partial.jsonl" || echo '{"error":"scenario_failed"}' > "$OUTPUT_DIR/scenario-b-partial.jsonl"
    echo "  Done: scenario-b-partial.jsonl"
else
    echo '{"error":"claude_not_found"}' > "$OUTPUT_DIR/scenario-b-partial.jsonl"
fi

# --- Scenario C: Tool use ---
echo "[6/9] Scenario C: Tool use (tool_use_block, tool_result_block, user_message)..."
if command -v claude &> /dev/null; then
    echo "Read the first 3 lines of mix.exs" | claude --output-format stream-json --verbose --max-turns 1 -p 2>/dev/null \
        > "$OUTPUT_DIR/scenario-c-tool.jsonl" || echo '{"error":"scenario_failed"}' > "$OUTPUT_DIR/scenario-c-tool.jsonl"
    echo "  Done: scenario-c-tool.jsonl"
else
    echo '{"error":"claude_not_found"}' > "$OUTPUT_DIR/scenario-c-tool.jsonl"
fi

# --- Scenario D: Error max turns ---
echo "[7/9] Scenario D: Error max turns (result with error_max_turns)..."
if command -v claude &> /dev/null; then
    echo "Create a file called /tmp/test_sync.txt with hello world, then read it back" | claude --output-format stream-json --verbose --max-turns 1 -p 2>/dev/null \
        > "$OUTPUT_DIR/scenario-d-error.jsonl" || echo '{"error":"scenario_failed"}' > "$OUTPUT_DIR/scenario-d-error.jsonl"
    echo "  Done: scenario-d-error.jsonl"
else
    echo '{"error":"claude_not_found"}' > "$OUTPUT_DIR/scenario-d-error.jsonl"
fi

# --- Scenario F: Extended thinking ---
echo "[8/9] Scenario F: Extended thinking (thinking_block)..."
if command -v claude &> /dev/null; then
    echo "Think step by step about why 17 is prime" | claude --output-format stream-json --verbose --max-turns 1 --model claude-opus-4-6 -p 2>/dev/null \
        > "$OUTPUT_DIR/scenario-f-thinking.jsonl" || echo '{"error":"scenario_failed_or_thinking_not_available"}' > "$OUTPUT_DIR/scenario-f-thinking.jsonl"
    echo "  Done: scenario-f-thinking.jsonl"
else
    echo '{"error":"claude_not_found"}' > "$OUTPUT_DIR/scenario-f-thinking.jsonl"
fi

# --- Python SDK via gh ---
echo "[9/9] Fetching Python SDK sources via gh..."
if command -v gh &> /dev/null; then
    # types.py - canonical message/content type definitions
    gh api repos/anthropics/claude-agent-sdk-python/contents/src/claude_agent_sdk/types.py --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-types.py" 2>/dev/null || echo "# FAILED to fetch types.py" > "$OUTPUT_DIR/python-sdk-types.py"
    echo "  Done: python-sdk-types.py"

    # subprocess_cli.py - CLI flag mapping
    gh api repos/anthropics/claude-agent-sdk-python/contents/src/claude_agent_sdk/_internal/transport/subprocess_cli.py --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-subprocess-cli.py" 2>/dev/null || echo "# FAILED to fetch subprocess_cli.py" > "$OUTPUT_DIR/python-sdk-subprocess-cli.py"
    echo "  Done: python-sdk-subprocess-cli.py"
else
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-types.py"
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-subprocess-cli.py"
    echo "  WARNING: gh CLI not found, skipping Python SDK fetch"
fi

echo ""
echo "=== Capture Complete ==="
echo ""
echo "Files in $OUTPUT_DIR:"
ls -la "$OUTPUT_DIR/"
echo ""
echo "Next step: Tell Claude to read the captured data and analyze it:"
echo '  "Read .claude/skills/cli-sync/captured/ and perform a CLI sync analysis"'
