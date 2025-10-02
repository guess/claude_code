# P0: Tool Control Fixes

**Status**: ✅ COMPLETE
**Completed**: 2025-10-02
**Original Effort**: ~4 hours

## Objective

Fix format bugs in `--allowedTools` and `--disallowedTools` CLI flag handling to ensure tool restriction features work correctly.

## Problem

The SDK currently implements tool control options (`:allowed_tools`, `:disallowed_tools`) but there's a suspected format bug in how the lists are converted to CLI flags. The code joins tool names with commas (`Enum.join(value, ",")`), but this may not match what the CLI expects.

## Current Implementation

Located in `/Users/steve/repos/guess/claude_code/lib/claude_code/options.ex`:

```elixir
defp convert_option_to_cli_flag(:allowed_tools, value) when is_list(value) do
  tools_csv = Enum.join(value, ",")
  {"--allowedTools", tools_csv}
end

defp convert_option_to_cli_flag(:disallowed_tools, value) when is_list(value) do
  tools_csv = Enum.join(value, ",")
  {"--disallowedTools", tools_csv}
end
```

## Scope

1. **Investigate actual CLI format**
   - Run real `claude` command with `--allowedTools` flag
   - Determine correct format (CSV? Multiple flags? JSON array?)
   - Document findings

2. **Write failing tests first**
   - Test with simple tools: `["View", "Edit"]`
   - Test with glob patterns: `["Bash(git:*)"]`
   - Test with mixed cases
   - Verify CLI actually respects restrictions

3. **Fix implementation**
   - Update `convert_option_to_cli_flag/2` functions
   - Ensure proper escaping if needed
   - Update validation if format requires it

4. **Verify permission-prompt-tool**
   - Add test for `:permission_prompt_tool` option
   - Ensure flag conversion is correct
   - Test end-to-end with MCP tool

## Success Criteria

- [x] CLI format documented with examples
- [x] Test suite passes with real CLI
- [x] Tool restrictions actually work (verified manually)
- [x] Test coverage >95% for options.ex
- [x] Documentation updated with working examples

## Resolution

The tool control features (`--allowedTools` and `--disallowedTools`) were tested with the real CLI and confirmed to work correctly with the existing CSV format implementation. No bugs were found - the implementation is working as expected.

## Files to Modify

- `/lib/claude_code/options.ex` - Fix flag conversion
- `/test/claude_code/options_test.exs` - Add comprehensive tests
- `/test/claude_code/cli_integration_test.exs` - Add end-to-end test
- `/examples/tool_restrictions.exs` - Add working example

## Dependencies

None - can be implemented immediately

## Notes

From code inspection, tests exist but may not be testing the actual CLI behavior:
```
test/claude_code/options_test.exs:      assert "--allowedTools" in args
```

This only verifies the flag name exists, not that the format is correct.
