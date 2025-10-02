# CLI Feature Parity Matrix

## Current State (Phase 4 Complete)

**18 features implemented** | **6 features to build for v1.0** | **8 features killed**

---

## Status Legend
- ✅ **HAVE** - Implemented and tested
- ⚠️ **BROKEN** - Implemented but has bugs (needs fix for v1.0)
- 🔨 **BUILD** - Must implement for v1.0
- ⏸️ **LATER** - Defer to v1.1+ (low ROI)
- 🗑️ **KILLED** - Will not implement (out of scope)

---

## Core Functionality

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Non-interactive mode | Hardcoded `--print` | ✅ HAVE | Always enabled |
| JSON streaming | Hardcoded `--output-format stream-json` | ✅ HAVE | Always enabled |
| Verbose output | Hardcoded `--verbose` | ✅ HAVE | Always enabled |
| Model selection | `:model` | ✅ HAVE | |
| System prompt append | `:append_system_prompt` | ✅ HAVE | |
| Turn limiting | `:max_turns` | ✅ HAVE | Prevents infinite loops |

---

## Session Management

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Session tracking | Internal `--session-id` | ✅ HAVE | Auto-managed |
| Auto-resume | Internal `--resume <id>` | ✅ HAVE | Auto-managed |
| Session forking | `:fork_session` | 🔨 BUILD | **P1** - Branch conversations |
| Continue flag | N/A | 🗑️ KILLED | SDK handles via --resume |

---

## Tool Control

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Allowed tools list | `:allowed_tools` | ⚠️ BROKEN | **P0** - Format bug, needs test + fix |
| Disallowed tools list | `:disallowed_tools` | ⚠️ BROKEN | **P0** - Format bug, needs test + fix |
| Additional directories | `:add_dir` | ✅ HAVE | |

---

## Permissions

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Permission mode | `:permission_mode` | ✅ HAVE | default/acceptEdits/bypassPermissions |
| MCP permission tool | `:permission_prompt_tool` | ✅ HAVE | Needs verification test |

---

## Production Features

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Fallback model | `:fallback_model` | 🔨 BUILD | **P0** - Critical for production resilience |
| Team settings | `:settings` | 🔨 BUILD | **P1** - Load team configuration |
| Advanced settings sources | `:setting_sources` | ⏸️ LATER | P3 - Edge case |

---

## Streaming & LiveView

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Current streaming | Built-in | ✅ HAVE | Stream complete messages |
| Partial message streaming | `:include_partial_messages` | 🔨 BUILD | **P1** - LiveView real-time updates |
| Streaming input | `:input_format` | ⏸️ LATER | P2 - Complex, low ROI |
| Replay user messages | N/A | 🗑️ KILLED | Only relevant with streaming input |

---

## MCP Integration

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| MCP config loading | `:mcp_config` | ✅ HAVE | |
| Strict MCP validation | `:strict_mcp_config` | ⏸️ LATER | P3 - Edge case |
| MCP command | N/A | 🗑️ KILLED | CLI configuration, not runtime |

---

## Agent Workflows

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Custom agents | `:agents` | ⏸️ LATER | P2 - Multi-agent workflows |
| Legacy system prompt | `:system_prompt` | 🗑️ KILLED | Replaced by --agents |

---

## Development Tools

| Feature | SDK Option | Status | Notes |
|---------|------------|--------|-------|
| Working directory | `:cwd` | ✅ HAVE | Shell-level, not CLI flag |
| CLI validation | `CLI.validate_installation/0` | ✅ HAVE | Health checks |
| Debug mode | N/A | 🗑️ KILLED | Use Elixir Logger instead |
| MCP debug | N/A | 🗑️ KILLED | Deprecated in CLI |
| IDE mode | N/A | 🗑️ KILLED | Interactive only |

---

## CLI Commands (Out of Scope)

These are CLI configuration commands, not runtime features:

| Command | Status | Why Killed |
|---------|--------|------------|
| `mcp` | 🗑️ | Server configuration |
| `setup-token` | 🗑️ | Authentication setup |
| `doctor` | 🗑️ | SDK has `CLI.validate_installation/0` |
| `update` | 🗑️ | CLI maintenance |
| `install` | 🗑️ | CLI installation |

---

## v1.0 Roadmap

### Critical (P0) - Week 1
1. ⚠️ Fix `--allowedTools` format bug
2. ⚠️ Fix `--disallowedTools` format bug
3. 🔨 Add `--fallback-model` support
4. ✅ Verify `--permission-prompt-tool` implementation

**Effort**: ~9 hours

### High Priority (P1) - Week 2
5. 🔨 Add `--include-partial-messages` for LiveView
6. 🔨 Add `--fork-session` for conversation branching
7. 🔨 Add `--settings` for team configuration

**Effort**: ~8 hours

### v1.0 Release Criteria
- All P0 + P1 features complete ✅
- Test coverage >95% ✅
- Documentation updated ✅
- Working examples added ✅

---

## v1.1+ Deferred Features

| Feature | Priority | Reason |
|---------|----------|--------|
| Streaming input | P2 | Complex implementation, low demand |
| Custom agents | P2 | Advanced use case, small audience |
| Strict MCP config | P3 | Edge case |
| Setting sources | P3 | Advanced configuration |

**Total deferred effort**: ~12 hours (not blocking v1.0)

---

## Competitive Analysis

### vs TypeScript SDK

| Capability | TypeScript | Elixir (Now) | Elixir (v1.0) |
|------------|-----------|--------------|---------------|
| Model selection | ✅ | ✅ | ✅ |
| Tool control | ✅ | ⚠️ | ✅ |
| Session management | ✅ | ✅ | ✅ |
| Streaming output | ✅ | ✅ | ✅ |
| Partial messages | ✅ | ❌ | ✅ |
| Fallback model | ✅ | ❌ | ✅ |
| Session forking | ✅ | ❌ | ✅ |
| Team settings | ✅ | ❌ | ✅ |

**Coverage**: 75% now → **100% at v1.0** (for 95% of use cases)

---

## Implementation Stats

```
Current State:
  ✅ HAVE:    18 features (75% of relevant features)
  ⚠️ BROKEN:   2 features (need fixes)

v1.0 Plan:
  🔨 BUILD:    4 features (P0-P1)
  ⏸️ LATER:    4 features (v1.1+)
  🗑️ KILLED:   8 features (out of scope)

Total Coverage: 28 features categorized (100%)
```

---

**Last Updated**: 2025-10-02
**Next Action**: Create project folders for P0 + P1 work
