# P0: Production Features

**Status**: Critical - Blocking v1.0
**Effort**: ~5 hours
**Priority**: Must complete in Week 1

## Objective

Add production-critical resilience features to the SDK, specifically fallback model support to prevent service disruptions when primary models are unavailable.

## Problem

Production applications need graceful degradation when primary models fail or are unavailable. The TypeScript SDK supports `--fallback-model`, but the Elixir SDK does not. This is a blocker for production deployments.

## Scope

### 1. Add `--fallback-model` Support (~4 hours)

**What**: Automatic fallback to alternate model when primary model fails

**Implementation**:
- Add `:fallback_model` option to schema in `options.ex`
- Map to `--fallback-model` CLI flag
- Validate model name format
- Add tests for fallback scenarios
- Document behavior in module docs

**Files**:
- `/lib/claude_code/options.ex` - Add option
- `/test/claude_code/options_test.exs` - Test flag conversion
- `/test/claude_code/session_test.exs` - Test with real session
- `/examples/fallback_model.exs` - Show production pattern

**CLI Flag Format**:
```bash
claude --model sonnet --fallback-model haiku "query"
```

**Example Usage**:
```elixir
{:ok, session} = ClaudeCode.start_link(
  api_key: api_key,
  model: "opus",
  fallback_model: "sonnet"  # Falls back if opus unavailable
)
```

### 2. Verify Permission Prompt Tool (~1 hour)

**What**: Ensure `--permission-prompt-tool` works correctly

**Implementation**:
- Add integration test with mock MCP server
- Verify flag format matches CLI expectations
- Document MCP permission flow
- Add example if not already present

**Files**:
- `/test/claude_code/mcp_integration_test.exs` - New test file
- `/lib/claude_code/options.ex` - Verify implementation
- `/examples/mcp_permissions.exs` - Show permission flow

## Success Criteria

- [ ] `:fallback_model` option implemented and tested
- [ ] CLI flag conversion verified correct
- [ ] Integration test proves fallback works
- [ ] Documentation includes production best practices
- [ ] Example shows resilient production setup
- [ ] `:permission_prompt_tool` verified working
- [ ] Test coverage >95%

## Dependencies

- P0: Tool Control Fixes (should complete first for clean test environment)

## Notes

**Production Impact**: This is the #1 blocker for production usage. Applications cannot rely on a single model without fallback capability.

**Related Options** (defer to v1.1):
- `--settings` - Team configuration (P1)
- `--setting-sources` - Advanced config (P3)
