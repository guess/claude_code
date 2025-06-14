#!/bin/bash

# Direct shell script to capture Claude CLI output
# This bypasses Elixir in case there are issues with the Elixir script

set -e

# Check if claude CLI exists
if ! command -v claude &> /dev/null; then
    echo "❌ Claude CLI not found!"
    echo "Please ensure 'claude' is installed and in your PATH"
    echo ""
    echo "You can install it with:"
    echo "  npm install -g @anthropic-ai/claude-cli"
    exit 1
fi

# Check for API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ ANTHROPIC_API_KEY environment variable not set!"
    exit 1
fi

echo "Found claude CLI at: $(which claude)"
echo "Creating test fixtures directory..."

mkdir -p test/fixtures/cli_messages

echo ""
echo "📝 Capturing simple hello response..."
echo "Say hello" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/simple_hello.json || true

echo "📝 Capturing math calculation..."
echo "What is 2 + 2?" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/math_calculation.json || true

echo "📝 Capturing file listing (with tool use)..."
echo "What files are in the current directory?" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/file_listing.json || true

echo "📝 Capturing file creation (with tool use)..."
echo "Create a file named test.txt with the content 'Hello from Claude'" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/create_file.json || true

echo "📝 Capturing file read (with tool use)..."
echo "Read the README.md file and tell me what this project is about" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/read_file.json || true

echo "📝 Capturing error case (with tool use)..."
echo "Read a file that does not exist: /nonexistent/file.txt" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/error_case.json || true

echo ""
echo "📝 Capturing permission denial cases (without skip)..."
echo ""

echo "📝 Capturing file creation WITHOUT permissions (should be denied)..."
echo "Create a file named denied.txt with content 'This should be denied'" | claude --output-format stream-json --verbose --print 2>&1 > test/fixtures/cli_messages/create_file_denied.json || true

echo "📝 Capturing file read WITHOUT permissions (may be allowed in default mode)..."
echo "Read the README.md file" | claude --output-format stream-json --verbose --print 2>&1 > test/fixtures/cli_messages/read_file_default.json || true

echo ""
echo "📝 Testing permission-related scenarios..."
echo ""

echo "📝 Capturing with skipped permissions (dangerous mode)..."
echo "Create a file named skip_test.txt with content 'Permissions skipped'" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/permission_skip.json || true

echo "📝 Capturing with allowed tools (Read only)..."
echo "Read the README.md file then try to create a file" | claude --output-format stream-json --verbose --print --allowedTools "Read" 2>&1 > test/fixtures/cli_messages/allowed_tools_read.json || true

echo "📝 Capturing with disallowed tools (no Write)..."
echo "Create a file named blocked.txt" | claude --output-format stream-json --verbose --print --disallowedTools "Write" 2>&1 > test/fixtures/cli_messages/disallowed_write.json || true

echo "📝 Capturing complex tool chain (with permissions)..."
echo "Read the mix.exs file, extract the version number, and create a VERSION.txt file with that version" | claude --output-format stream-json --verbose --print --dangerously-skip-permissions 2>&1 > test/fixtures/cli_messages/complex_tool_chain.json || true

echo ""
echo "✅ Capture complete! Check test/fixtures/cli_messages/"
echo ""
echo "You can also run individual commands like:"
echo '  echo "Your query" | claude --output-format stream-json --verbose --print'
echo ""
echo "To format the JSON output nicely:"
echo "  cat test/fixtures/cli_messages/simple_hello.json | jq ."
