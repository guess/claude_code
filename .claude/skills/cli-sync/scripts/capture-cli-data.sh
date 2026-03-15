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
#   - Python SDK types.py, subprocess_cli.py, query.py, message_parser.py, client.py (via gh)
#   - TypeScript SDK sdk.d.ts type definitions (via npm/unpkg)
#   - Anthropic API types (BetaRawMessageStreamEvent etc. from @anthropic-ai/sdk)
#   - SDK version tracking files
#   - Official documentation (CLI reference, hooks, plugins, TS/Python SDK docs)
#
# After running, tell Claude:
#   "Read the captured CLI data in .claude/skills/cli-sync/captured/ and perform a sync analysis"

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/../captured}"

mkdir -p "$OUTPUT_DIR"

echo "=== CLI Sync Data Capture ==="
echo "Output directory: $OUTPUT_DIR"
echo ""

# --- Version Info ---
echo "[1/8] Capturing CLI version..."
if command -v claude &> /dev/null; then
    claude --version 2>/dev/null > "$OUTPUT_DIR/cli-version.txt" || echo "FAILED" > "$OUTPUT_DIR/cli-version.txt"
    echo "  Done: cli-version.txt"
else
    echo "ERROR: claude not found in PATH" > "$OUTPUT_DIR/cli-version.txt"
    echo "  WARNING: claude CLI not found"
fi

# --- Help Output ---
echo "[2/8] Capturing CLI --help..."
if command -v claude &> /dev/null; then
    claude --help 2>&1 > "$OUTPUT_DIR/cli-help.txt" || echo "FAILED" > "$OUTPUT_DIR/cli-help.txt"
    echo "  Done: cli-help.txt"
else
    echo "SKIPPED: claude not found" > "$OUTPUT_DIR/cli-help.txt"
fi

# --- Bundled Version ---
echo "[3/8] Capturing bundled version..."
INSTALLER_FILE="$PROJECT_ROOT/lib/claude_code/adapter/port/installer.ex"
if [ -f "$INSTALLER_FILE" ]; then
    BUNDLED=$(grep '@default_cli_version' "$INSTALLER_FILE" | head -1 | grep -o '"[^"]*"' | tr -d '"')
    echo "bundled_version=$BUNDLED" > "$OUTPUT_DIR/bundled-version.txt"
    echo "  Bundled: $BUNDLED"
else
    echo "bundled_version=NOT_FOUND" > "$OUTPUT_DIR/bundled-version.txt"
    echo "  WARNING: installer.ex not found"
fi

# --- Python SDK via gh ---
echo "[4/8] Fetching Python SDK sources via gh..."
PYTHON_REPO="anthropics/claude-agent-sdk-python"
PYTHON_SRC="src/claude_agent_sdk"
if command -v gh &> /dev/null; then
    # types.py - canonical message/content type definitions
    gh api "repos/$PYTHON_REPO/contents/$PYTHON_SRC/types.py" --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-types.py" 2>/dev/null || echo "# FAILED to fetch types.py" > "$OUTPUT_DIR/python-sdk-types.py"
    echo "  Done: python-sdk-types.py"

    # subprocess_cli.py - CLI flag mapping
    gh api "repos/$PYTHON_REPO/contents/$PYTHON_SRC/_internal/transport/subprocess_cli.py" --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-subprocess-cli.py" 2>/dev/null || echo "# FAILED to fetch subprocess_cli.py" > "$OUTPUT_DIR/python-sdk-subprocess-cli.py"
    echo "  Done: python-sdk-subprocess-cli.py"

    # query.py - control protocol handling, hook dispatch, can_use_tool routing
    gh api "repos/$PYTHON_REPO/contents/$PYTHON_SRC/_internal/query.py" --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-query.py" 2>/dev/null || echo "# FAILED to fetch query.py" > "$OUTPUT_DIR/python-sdk-query.py"
    echo "  Done: python-sdk-query.py"

    # message_parser.py - message type dispatch and field extraction
    gh api "repos/$PYTHON_REPO/contents/$PYTHON_SRC/_internal/message_parser.py" --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-message-parser.py" 2>/dev/null || echo "# FAILED to fetch message_parser.py" > "$OUTPUT_DIR/python-sdk-message-parser.py"
    echo "  Done: python-sdk-message-parser.py"

    # client.py (internal) - option validation, mutual exclusion, preprocessing
    gh api "repos/$PYTHON_REPO/contents/$PYTHON_SRC/_internal/client.py" --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-client.py" 2>/dev/null || echo "# FAILED to fetch _internal/client.py" > "$OUTPUT_DIR/python-sdk-client.py"
    echo "  Done: python-sdk-client.py"

    # client.py (public) - public client API surface
    gh api "repos/$PYTHON_REPO/contents/$PYTHON_SRC/client.py" --jq '.content' 2>/dev/null | base64 -d \
        > "$OUTPUT_DIR/python-sdk-public-client.py" 2>/dev/null || echo "# FAILED to fetch client.py" > "$OUTPUT_DIR/python-sdk-public-client.py"
    echo "  Done: python-sdk-public-client.py"
else
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-types.py"
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-subprocess-cli.py"
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-query.py"
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-message-parser.py"
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-client.py"
    echo "# gh CLI not found - install with: brew install gh" > "$OUTPUT_DIR/python-sdk-public-client.py"
    echo "  WARNING: gh CLI not found, skipping Python SDK fetch"
fi

# --- TypeScript SDK types via npm/unpkg ---
echo "[5/8] Fetching TypeScript SDK type definitions..."
# Get latest version from npm registry
TS_SDK_VERSION=$(curl -s "https://registry.npmjs.org/@anthropic-ai/claude-agent-sdk/latest" 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$TS_SDK_VERSION" ]; then
    echo "$TS_SDK_VERSION" > "$OUTPUT_DIR/ts-sdk-version.txt"
    echo "  TS SDK version: $TS_SDK_VERSION"

    # Download sdk.d.ts from unpkg (canonical type definitions with SDKMessage union)
    curl -sL "https://unpkg.com/@anthropic-ai/claude-agent-sdk@$TS_SDK_VERSION/sdk.d.ts" \
        > "$OUTPUT_DIR/ts-sdk-types.d.ts" 2>/dev/null || echo "// FAILED to fetch sdk.d.ts" > "$OUTPUT_DIR/ts-sdk-types.d.ts"
    echo "  Done: ts-sdk-types.d.ts"
else
    echo "FAILED" > "$OUTPUT_DIR/ts-sdk-version.txt"
    echo "// FAILED to fetch - npm registry unreachable" > "$OUTPUT_DIR/ts-sdk-types.d.ts"
    echo "  WARNING: Could not reach npm registry for TS SDK version"
fi

# --- Anthropic API types (streaming events, deltas, content blocks) ---
echo "[6/8] Fetching Anthropic API type definitions..."
ANTHROPIC_SDK_VERSION=$(curl -s "https://registry.npmjs.org/@anthropic-ai/sdk/latest" 2>/dev/null | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$ANTHROPIC_SDK_VERSION" ]; then
    echo "$ANTHROPIC_SDK_VERSION" > "$OUTPUT_DIR/anthropic-sdk-version.txt"
    echo "  Anthropic SDK version: $ANTHROPIC_SDK_VERSION"

    # BetaRawMessageStreamEvent and related types (content block deltas, start/stop events)
    curl -sL "https://unpkg.com/@anthropic-ai/sdk@$ANTHROPIC_SDK_VERSION/resources/beta/messages/messages.d.ts" \
        > "$OUTPUT_DIR/anthropic-api-messages.d.ts" 2>/dev/null || echo "// FAILED to fetch messages.d.ts" > "$OUTPUT_DIR/anthropic-api-messages.d.ts"
    echo "  Done: anthropic-api-messages.d.ts"
else
    echo "FAILED" > "$OUTPUT_DIR/anthropic-sdk-version.txt"
    echo "// FAILED to fetch - npm registry unreachable" > "$OUTPUT_DIR/anthropic-api-messages.d.ts"
    echo "  WARNING: Could not reach npm registry for Anthropic SDK version"
fi

# --- Python SDK version ---
echo "[7/8] Recording Python SDK version..."
if command -v gh &> /dev/null; then
    PY_SDK_VERSION=$(gh api repos/anthropics/claude-agent-sdk-python/releases/latest --jq '.tag_name' 2>/dev/null)
    if [ -n "$PY_SDK_VERSION" ]; then
        echo "$PY_SDK_VERSION" > "$OUTPUT_DIR/py-sdk-version.txt"
        echo "  Python SDK version: $PY_SDK_VERSION"
    else
        echo "FAILED" > "$OUTPUT_DIR/py-sdk-version.txt"
        echo "  WARNING: Could not fetch Python SDK version"
    fi
else
    echo "FAILED - gh not found" > "$OUTPUT_DIR/py-sdk-version.txt"
    echo "  WARNING: gh CLI not found, skipping Python SDK version"
fi

# --- Official Documentation ---
echo "[8/9] Fetching official documentation..."
DOCS_DIR="$OUTPUT_DIR/docs"
mkdir -p "$DOCS_DIR"

DOC_URLS=(
    "https://code.claude.com/docs/en/cli-reference.md"
    "https://code.claude.com/docs/en/hooks.md"
    "https://code.claude.com/docs/en/plugins-reference.md"
    "https://platform.claude.com/docs/en/agent-sdk/typescript.md"
    "https://platform.claude.com/docs/en/agent-sdk/python.md"
)

for url in "${DOC_URLS[@]}"; do
    filename=$(basename "$url")
    curl -sL "$url" > "$DOCS_DIR/$filename" 2>/dev/null || echo "# FAILED to fetch $url" > "$DOCS_DIR/$filename"
    # Check if we got a meaningful file (not an HTML error page)
    if head -1 "$DOCS_DIR/$filename" | grep -q '<!DOCTYPE\|<html'; then
        echo "  WARNING: $filename returned HTML (may be 404)"
    else
        echo "  Done: docs/$filename"
    fi
done

# --- Summary ---
echo "[9/9] Capture summary"
echo ""
echo "=== Capture Complete ==="
echo ""
echo "Files in $OUTPUT_DIR:"
ls -la "$OUTPUT_DIR/"
echo ""
echo "Next step: Tell Claude to read the captured data and analyze it:"
echo '  "Read .claude/skills/cli-sync/captured/ and perform a CLI sync analysis"'
