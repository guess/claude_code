#!/bin/bash

# Clean up any test files created by the capture scripts
echo "Cleaning up test files created during capture..."

rm -f test.txt
rm -f auto_test.txt
rm -f skip_test.txt
rm -f blocked.txt
rm -f denied.txt
rm -f VERSION.txt

echo "✅ Cleanup complete"