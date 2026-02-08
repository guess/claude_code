#!/bin/bash
# Run a test query and capture full JSON output for schema comparison
#
# Usage: ./run-test-query.sh [output_file]
#
# If output_file is not specified, prints to stdout

set -e

OUTPUT_FILE="${1:-}"
QUERY="What is 2+2? Answer briefly."

echo "Running test query to capture CLI JSON output..." >&2

if [ -n "$OUTPUT_FILE" ]; then
    echo "$QUERY" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null > "$OUTPUT_FILE"
    echo "Output saved to: $OUTPUT_FILE" >&2
    echo "" >&2
    echo "Message types captured:" >&2
    grep -o '"type":"[^"]*"' "$OUTPUT_FILE" | sort | uniq -c >&2
else
    echo "$QUERY" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null
fi
