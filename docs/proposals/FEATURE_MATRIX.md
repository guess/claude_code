# CLI Feature Parity Matrix

## Current State (Phase 4 Complete)

**24 features implemented** | **2 features to build for v1.0** | **20+ features deferred** | **12 features killed**

---

## Status Legend
- ✅ **HAVE** - Implemented and tested
- ⚠️ **BROKEN** - Implemented but has bugs (needs fix for v1.0)
- 🔨 **BUILD** - Must implement for v1.0
- ⏸️ **LATER** - Defer to v1.1+ (low ROI or complex)
- 🗑️ **KILLED** - Will not implement (out of scope or N/A for Elixir)

---

## Core Functionality

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Non-interactive mode | Hardcoded | Hardcoded `--print` | ✅ HAVE | Always enabled |
| JSON streaming | Hardcoded | Hardcoded `--output-format stream-json` | ✅ HAVE | Always enabled |
| Verbose output | Hardcoded | Hardcoded `--verbose` | ✅ HAVE | Always enabled |
| Model selection | `model` | `:model` | ✅ HAVE | |
| System prompt override | `systemPrompt` | `:system_prompt` | ✅ HAVE | String override |
| System prompt append | `systemPrompt.append` | `:append_system_prompt` | ✅ HAVE | |
| Turn limiting | `maxTurns` | `:max_turns` | ✅ HAVE | Prevents infinite loops |
| Working directory | `cwd` | `:cwd` | ✅ HAVE | Shell-level via subprocess |

---

## Session Management

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Session tracking | Internal | Internal `--session-id` | ✅ HAVE | Auto-managed |
| Auto-resume | `resume` | Internal `--resume <id>` | ✅ HAVE | Auto-managed via session_id |
| Session forking | `forkSession` | `:fork_session` | 🔨 BUILD | **P1** - Branch conversations |
| Resume at message | `resumeSessionAt` | N/A | ⏸️ LATER | P3 - Resume at specific UUID |
| Continue flag | `continue` | N/A | 🗑️ KILLED | SDK handles via --resume |

---

## Tool Control

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Allowed tools list | `allowedTools` | `:allowed_tools` | ✅ HAVE | CSV format |
| Disallowed tools list | `disallowedTools` | `:disallowed_tools` | ✅ HAVE | CSV format |
| Additional directories | `additionalDirectories` | `:add_dir` | ✅ HAVE | Multiple `--add-dir` flags |
| Tool preset | `tools` | N/A | ⏸️ LATER | P3 - `{ type: 'preset', preset: 'claude_code' }` |

---

## Permissions

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Permission mode | `permissionMode` | `:permission_mode` | ✅ HAVE | default/acceptEdits/bypassPermissions/plan |
| MCP permission tool | `permissionPromptToolName` | `:permission_prompt_tool` | ✅ HAVE | |
| Custom permission function | `canUseTool` | `:permission_handler` | ✅ HAVE | Module-based handler |
| Bypass permissions flag | `allowDangerouslySkipPermissions` | N/A | ⏸️ LATER | P3 - Safety flag for bypassPermissions |

---

## Production Features

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Fallback model | `fallbackModel` | `:fallback_model` | 🔨 BUILD | **P0** - Critical for production resilience |
| Team settings | N/A (via settingSources) | `:settings` | ✅ HAVE | File path, JSON string, or map (auto-encoded) |
| Settings sources | `settingSources` | `:setting_sources` | ✅ HAVE | List of sources: user, project, local |
| Budget limiting | `maxBudgetUsd` | `:max_budget_usd` | ⏸️ LATER | P2 - Cost control |
| Query timeout | N/A | `:timeout` | ✅ HAVE | Elixir-only, 300s default |
| Tool callback | N/A | `:tool_callback` | ✅ HAVE | Elixir-only, post-execution monitoring |

---

## Streaming & LiveView

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Stream complete messages | Built-in | Built-in | ✅ HAVE | `query_stream/3` |
| Partial message streaming | `includePartialMessages` | `:include_partial_messages` | ✅ HAVE | Character-level for LiveView |
| Text delta extraction | N/A | `Stream.text_deltas/1` | ✅ HAVE | Elixir stream utility |
| Content delta extraction | N/A | `Stream.content_deltas/1` | ✅ HAVE | All delta types |
| Buffered text streaming | N/A | `Stream.buffered_text/1` | ✅ HAVE | Sentence boundary buffering |
| Streaming input | `prompt: AsyncIterable` | `:input_format` | ⏸️ LATER | P2 - Complex, low ROI |
| Replay user messages | N/A | N/A | 🗑️ KILLED | Only relevant with streaming input |

---

## MCP Integration

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| MCP config file | N/A | `:mcp_config` | ✅ HAVE | Path to JSON config file |
| MCP servers map | `mcpServers` | `:mcp_servers` | ✅ HAVE | Supports stdio, Hermes modules |
| Strict MCP validation | `strictMcpConfig` | `:strict_mcp_config` | ⏸️ LATER | P3 - Edge case |
| MCP server status | `mcpServerStatus()` | N/A | ⏸️ LATER | P3 - Query method |
| MCP command | N/A | N/A | 🗑️ KILLED | CLI configuration, not runtime |

---

## Agent Workflows

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Custom agents | `agents` | `:agents` | ✅ HAVE | Map of agent configs (description, prompt, tools, model) |
| System prompt override | `systemPrompt` | `:system_prompt` | ✅ HAVE | Override default system prompt |
| System prompt preset | `systemPrompt.preset` | N/A | ⏸️ LATER | P3 - `{ type: 'preset', preset: 'claude_code' }` |

---

## Thinking & Extended Context

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Max thinking tokens | `maxThinkingTokens` | `:max_thinking_tokens` | ⏸️ LATER | P2 - Extended thinking control |
| Beta features | `betas` | `:betas` | ⏸️ LATER | P2 - e.g., context-1m-2025-08-07 |
| Structured outputs | `outputFormat` | `:output_format` | ⏸️ LATER | P2 - JSON schema outputs |

---

## Query Methods (Runtime Control)

| Feature | TS SDK Method | Elixir Method | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Interrupt query | `interrupt()` | N/A | ⏸️ LATER | P2 - Only for streaming input |
| Rewind files | `rewindFiles()` | N/A | ⏸️ LATER | P3 - Requires file checkpointing |
| Set permission mode | `setPermissionMode()` | N/A | ⏸️ LATER | P3 - Only for streaming input |
| Set model | `setModel()` | N/A | ⏸️ LATER | P3 - Only for streaming input |
| Set max thinking | `setMaxThinkingTokens()` | N/A | ⏸️ LATER | P3 - Only for streaming input |
| Get supported commands | `supportedCommands()` | N/A | ⏸️ LATER | P3 - Slash command discovery |
| Get supported models | `supportedModels()` | N/A | ⏸️ LATER | P3 - Model discovery |
| Get account info | `accountInfo()` | N/A | ⏸️ LATER | P3 - Account information |
| Get session ID | N/A | `get_session_id/1` | ✅ HAVE | Elixir-specific |
| Clear session | N/A | `clear/1` | ✅ HAVE | Elixir-specific |

---

## Hooks & Plugins

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Event hooks | `hooks` | N/A | ⏸️ LATER | P2 - PreToolUse, PostToolUse, etc. |
| Plugins | `plugins` | N/A | ⏸️ LATER | P3 - Local plugin loading |
| File checkpointing | `enableFileCheckpointing` | N/A | ⏸️ LATER | P3 - For file rewinding |

---

## Sandbox & Security

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| Sandbox enabled | `sandbox.enabled` | N/A | ⏸️ LATER | P3 - Command sandboxing |
| Auto-allow sandboxed | `sandbox.autoAllowBashIfSandboxed` | N/A | ⏸️ LATER | P3 |
| Excluded commands | `sandbox.excludedCommands` | N/A | ⏸️ LATER | P3 |
| Network sandbox | `sandbox.network` | N/A | ⏸️ LATER | P3 |

---

## Development Tools

| Feature | TS SDK Option | Elixir Option | Status | Notes |
|---------|---------------|---------------|--------|-------|
| CLI validation | N/A | `CLI.validate_installation/0` | ✅ HAVE | Health checks |
| Custom CLI path | `pathToClaudeCodeExecutable` | N/A | ⏸️ LATER | P3 - Use system PATH |
| Stderr callback | `stderr` | N/A | ⏸️ LATER | P3 - Stderr handling |
| Extra CLI args | `extraArgs` | N/A | ⏸️ LATER | P3 - Pass-through args |
| Abort controller | `abortController` | N/A | ⏸️ LATER | P3 - Cancellation |

---

## Runtime-Specific (Not Applicable to Elixir)

| Feature | TS SDK Option | Status | Notes |
|---------|---------------|--------|-------|
| JS runtime selection | `executable` | 🗑️ KILLED | N/A - Elixir runs on BEAM |
| Runtime args | `executableArgs` | 🗑️ KILLED | N/A - Elixir runs on BEAM |
| Environment variables | `env` | 🗑️ KILLED | Use OS environment |
| Debug mode | N/A | 🗑️ KILLED | Use Elixir Logger |
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

### Critical (P0)
1. 🔨 Add `--fallback-model` support

### High Priority (P1)
2. 🔨 Add `--fork-session` for conversation branching

### v1.0 Release Criteria
- All P0 + P1 features complete
- Test coverage >95% ✅
- Documentation updated ✅
- Working examples added ✅

---

## v1.1+ Deferred Features

### P2 - Medium Priority
| Feature | Reason |
|---------|--------|
| `maxBudgetUsd` | Cost control for production |
| `maxThinkingTokens` | Extended thinking control |
| `betas` | Beta feature enablement |
| `outputFormat` | Structured JSON outputs |
| `hooks` | Event hooks (PreToolUse, etc.) |
| `interrupt()` | Query cancellation |
| Streaming input | Complex, requires V2-style API |

### P3 - Low Priority
| Feature | Reason |
|---------|--------|
| `strictMcpConfig` | Edge case |
| `resumeSessionAt` | Resume at specific UUID |
| `sandbox` | Command sandboxing |
| `plugins` | Plugin loading |
| `enableFileCheckpointing` | File rewinding |
| Query runtime methods | setModel, setPermissionMode, etc. |
| `pathToClaudeCodeExecutable` | Custom CLI path |
| `allowDangerouslySkipPermissions` | Safety flag |

---

## Competitive Analysis

### vs TypeScript SDK v1

| Capability | TypeScript | Elixir (Now) | Elixir (v1.0) | Elixir (v1.1+) |
|------------|-----------|--------------|---------------|----------------|
| Model selection | ✅ | ✅ | ✅ | ✅ |
| Tool control | ✅ | ✅ | ✅ | ✅ |
| Session management | ✅ | ✅ | ✅ | ✅ |
| Streaming output | ✅ | ✅ | ✅ | ✅ |
| Partial messages | ✅ | ✅ | ✅ | ✅ |
| Custom agents | ✅ | ✅ | ✅ | ✅ |
| Team settings | ✅ | ✅ | ✅ | ✅ |
| MCP servers | ✅ | ✅ | ✅ | ✅ |
| Permission modes | ✅ | ✅ | ✅ | ✅ |
| Fallback model | ✅ | ❌ | ✅ | ✅ |
| Session forking | ✅ | ❌ | ✅ | ✅ |
| Budget limiting | ✅ | ❌ | ❌ | ✅ |
| Thinking tokens | ✅ | ❌ | ❌ | ✅ |
| Structured outputs | ✅ | ❌ | ❌ | ✅ |
| Hooks | ✅ | ❌ | ❌ | ✅ |
| Sandbox | ✅ | ❌ | ❌ | ✅ |
| Streaming input | ✅ | ❌ | ❌ | ⏸️ |

**Core Feature Coverage**: 92% now → **100% at v1.0** (for 95% of use cases)
**Full Feature Coverage**: ~65% now → ~70% at v1.0 → ~90% at v1.1

---

## Elixir-Specific Features (Not in TypeScript)

| Feature | Option | Status | Notes |
|---------|--------|--------|-------|
| GenServer process naming | `:name` | ✅ HAVE | OTP integration |
| Query timeout | `:timeout` | ✅ HAVE | Per-request timeout control |
| Tool callback | `:tool_callback` | ✅ HAVE | Post-execution monitoring |
| Permission handler module | `:permission_handler` | ✅ HAVE | Module-based (vs function) |
| Hermes MCP integration | `:mcp_servers` | ✅ HAVE | Native Hermes module support |
| Stream utilities | `ClaudeCode.Stream` | ✅ HAVE | Rich stream processing |
| Text delta extraction | `text_deltas/1` | ✅ HAVE | |
| Content delta extraction | `content_deltas/1` | ✅ HAVE | |
| Buffered text | `buffered_text/1` | ✅ HAVE | Sentence boundary buffering |
| Session ID access | `get_session_id/1` | ✅ HAVE | |
| Clear session | `clear/1` | ✅ HAVE | |

---

## Implementation Stats

```
Current State:
  ✅ HAVE:    24 core features (92% of core functionality)
  ⚠️ BROKEN:   0 features

v1.0 Plan:
  🔨 BUILD:    2 features (P0-P1)

Deferred:
  ⏸️ LATER:   20+ features (v1.1+)
  🗑️ KILLED:  12 features (out of scope or N/A)

TypeScript Parity:
  Core features: 92% → 100% at v1.0
  All features:  ~65% → ~90% at v1.1
```

---

## Message Types Supported

| Type | Status | Notes |
|------|--------|-------|
| System | ✅ HAVE | Init message with session info |
| Assistant | ✅ HAVE | Responses with content blocks |
| User | ✅ HAVE | Input and tool results |
| Result | ✅ HAVE | Final response with metrics |
| StreamEvent | ✅ HAVE | Partial message updates |

---

## Content Block Types Supported

| Type | Status | Notes |
|------|--------|-------|
| Text | ✅ HAVE | Text content |
| ToolUse | ✅ HAVE | Tool invocations |
| ToolResult | ✅ HAVE | Tool execution results |

---

**Last Updated**: 2025-12-29
**Reference**: TypeScript SDK v1 Documentation
**Next Action**: Add fallback model and session forking support
