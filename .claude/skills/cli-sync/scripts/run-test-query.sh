#!/bin/bash
# Run test queries to capture CLI JSON output for schema comparison
#
# Usage:
#   ./run-test-query.sh              # Run all scenarios, print to stdout
#   ./run-test-query.sh [output_dir] # Save each scenario to output_dir/
#   ./run-test-query.sh --scenario A # Run only scenario A
#
# Scenarios:
#   A - Basic query (system, assistant, result, text_block)
#   B - Partial streaming (partial_assistant)
#   C - Tool use (tool_use_block, tool_result_block, user_message)

set -e

SCENARIO="${1:-all}"
OUTPUT_DIR="${2:-}"

run_scenario_a() {
    echo "=== Scenario A: Basic Query ===" >&2
    echo "Triggers: system, assistant, result, text_block" >&2
    echo "What is 2+2?" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null
}

run_scenario_b() {
    echo "=== Scenario B: Partial Streaming ===" >&2
    echo "Triggers: partial_assistant" >&2
    echo "Count from 1 to 5" | claude --output-format stream-json --verbose --include-partial-messages --max-turns 1 2>/dev/null
}

run_scenario_c() {
    echo "=== Scenario C: Tool Use ===" >&2
    echo "Triggers: tool_use_block, tool_result_block, user_message" >&2
    echo "Read the first 3 lines of mix.exs" | claude --output-format stream-json --verbose --max-turns 1 2>/dev/null
}

save_or_print() {
    local scenario=$1
    local output

    case $scenario in
        A) output=$(run_scenario_a) ;;
        B) output=$(run_scenario_b) ;;
        C) output=$(run_scenario_c) ;;
    esac

    if [ -n "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
        echo "$output" > "$OUTPUT_DIR/scenario_${scenario}.json"
        echo "Saved to $OUTPUT_DIR/scenario_${scenario}.json" >&2
    else
        echo "$output"
    fi
    echo "" >&2
}

case $SCENARIO in
    --scenario)
        save_or_print "$2"
        ;;
    all|"")
        save_or_print A
        save_or_print B
        save_or_print C

        echo "=== Message types captured ===" >&2
        if [ -n "$OUTPUT_DIR" ]; then
            cat "$OUTPUT_DIR"/*.json | grep -o '"type":"[^"]*"' | sort | uniq -c >&2
        fi
        ;;
    *)
        echo "Usage: $0 [all|--scenario A|B|C] [output_dir]" >&2
        exit 1
        ;;
esac
