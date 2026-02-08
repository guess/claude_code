#!/bin/bash
# Compare installed CLI version with bundled SDK version
#
# Usage: ./compare-versions.sh

set -e

echo "=== CLI Version Comparison ==="
echo ""

# Get installed CLI version
if command -v claude &> /dev/null; then
    INSTALLED=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
    echo "Installed CLI version: $INSTALLED"
else
    echo "Installed CLI version: NOT FOUND"
    INSTALLED=""
fi

# Get bundled version from installer.ex
INSTALLER_FILE="lib/claude_code/installer.ex"
if [ -f "$INSTALLER_FILE" ]; then
    BUNDLED=$(grep '@default_cli_version' "$INSTALLER_FILE" | head -1 | grep -o '"[^"]*"' | tr -d '"')
    echo "Bundled SDK version:   $BUNDLED"
else
    echo "Bundled SDK version:   INSTALLER NOT FOUND"
    BUNDLED=""
fi

echo ""

# Compare
if [ -n "$INSTALLED" ] && [ -n "$BUNDLED" ]; then
    if [ "$INSTALLED" = "$BUNDLED" ]; then
        echo "Status: SYNCED"
    else
        echo "Status: OUT OF SYNC"
        echo ""
        echo "To update, edit lib/claude_code/installer.ex:"
        echo "  @default_cli_version \"$INSTALLED\""
    fi
else
    echo "Status: UNABLE TO COMPARE"
fi
