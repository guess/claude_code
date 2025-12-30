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

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Non-interactive mode | Hardcoded | Hardcoded | `--print` | ✅ HAVE | Always enabled |
| JSON streaming | Hardcoded | Hardcoded | `--output-format stream-json` | ✅ HAVE | Always enabled |
| Verbose output | Hardcoded | Hardcoded | `--verbose` | ✅ HAVE | Always enabled |
| Model selection | `model` | `model` | `:model` | ✅ HAVE | |
| System prompt override | `systemPrompt` | `system_prompt` | `:system_prompt` | ✅ HAVE | String override |
| System prompt append | `systemPrompt.append` | `system_prompt.append` | `:append_system_prompt` | ✅ HAVE | |
| System prompt preset | `systemPrompt.preset` | `SystemPromptPreset` | N/A | ⏸️ LATER | P3 - `claude_code` preset |
| Turn limiting | `maxTurns` | `max_turns` | `:max_turns` | ✅ HAVE | Prevents infinite loops |
| Working directory | `cwd` | `cwd` | `:cwd` | ✅ HAVE | Shell-level via subprocess |

---

## Session Management

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Session tracking | Internal | Internal | `--session-id` | ✅ HAVE | Auto-managed |
| Auto-resume | `resume` | `resume` | `--resume <id>` | ✅ HAVE | Auto-managed via session_id |
| Session forking | `forkSession` | `fork_session` | `:fork_session` | 🔨 BUILD | **P1** - Branch conversations |
| Resume at message | `resumeSessionAt` | N/A | N/A | ⏸️ LATER | P3 - Resume at specific UUID |
| Continue conversation | `continue` | `continue_conversation` | N/A | 🗑️ KILLED | SDK handles via --resume |
| Client class | N/A | `ClaudeSDKClient` | `ClaudeCode.Session` | ✅ HAVE | GenServer vs async class |

---

## Tool Control

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Allowed tools list | `allowedTools` | `allowed_tools` | `:allowed_tools` | ✅ HAVE | CSV format |
| Disallowed tools list | `disallowedTools` | `disallowed_tools` | `:disallowed_tools` | ✅ HAVE | CSV format |
| Additional directories | `additionalDirectories` | `add_dirs` | `:add_dir` | ✅ HAVE | Multiple `--add-dir` flags |
| Tool preset | `tools` | N/A | N/A | ⏸️ LATER | P3 - Preset tool sets |
| Custom tools decorator | N/A | `@tool` | N/A | ⏸️ LATER | P2 - Define tools in SDK |
| In-process MCP server | N/A | `create_sdk_mcp_server()` | N/A | ⏸️ LATER | P2 - SDK MCP servers |

---

## Permissions

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Permission mode | `permissionMode` | `permission_mode` | `:permission_mode` | ✅ HAVE | default/acceptEdits/bypassPermissions/plan |
| MCP permission tool | `permissionPromptToolName` | `permission_prompt_tool_name` | `:permission_prompt_tool` | ✅ HAVE | |
| Custom permission function | `canUseTool` | `can_use_tool` | `:permission_handler` | ✅ HAVE | Module-based handler (Elixir) |
| Bypass permissions flag | `allowDangerouslySkipPermissions` | N/A | N/A | ⏸️ LATER | P3 - Safety flag |

---

## Production Features

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Fallback model | `fallbackModel` | N/A | `:fallback_model` | 🔨 BUILD | **P0** - Production resilience |
| Team settings | `settingSources` | `settings` | `:settings` | ✅ HAVE | File path, JSON string, or map |
| Settings sources | `settingSources` | `setting_sources` | `:setting_sources` | ✅ HAVE | user, project, local |
| Budget limiting | `maxBudgetUsd` | N/A | `:max_budget_usd` | ⏸️ LATER | P2 - Cost control |
| Query timeout | N/A | N/A | `:timeout` | ✅ HAVE | Elixir-only, 300s default |
| Tool callback | N/A | N/A | `:tool_callback` | ✅ HAVE | Elixir-only, post-exec monitoring |
| User identifier | N/A | `user` | N/A | ⏸️ LATER | P3 - User tracking |

---

## Streaming & Real-time

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Stream complete messages | Built-in | `receive_messages()` | `query_stream/3` | ✅ HAVE | |
| Partial message streaming | `includePartialMessages` | `include_partial_messages` | `:include_partial_messages` | ✅ HAVE | Character-level |
| Text delta extraction | N/A | N/A | `Stream.text_deltas/1` | ✅ HAVE | Elixir stream utility |
| Content delta extraction | N/A | N/A | `Stream.content_deltas/1` | ✅ HAVE | All delta types |
| Buffered text streaming | N/A | N/A | `Stream.buffered_text/1` | ✅ HAVE | Sentence boundaries |
| Streaming input | `AsyncIterable` | `AsyncIterable` | N/A | ⏸️ LATER | P2 - Complex |
| Receive until result | N/A | `receive_response()` | `Stream.until_result/1` | ✅ HAVE | |

---

## MCP Integration

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| MCP config file | N/A | `mcp_servers` (path) | `:mcp_config` | ✅ HAVE | Path to JSON config |
| MCP servers map | `mcpServers` | `mcp_servers` (dict) | `:mcp_servers` | ✅ HAVE | stdio, SSE, HTTP, SDK |
| In-process MCP server | N/A | `McpSdkServerConfig` | Hermes modules | ✅ HAVE | Native module support |
| Strict MCP validation | `strictMcpConfig` | N/A | `:strict_mcp_config` | ⏸️ LATER | P3 - Edge case |
| MCP server status | `mcpServerStatus()` | N/A | N/A | ⏸️ LATER | P3 - Query method |

---

## Agent Workflows

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Custom agents | `agents` | `agents` | `:agents` | ✅ HAVE | Map of agent configs |
| Agent definition | `AgentConfig` | `AgentDefinition` | Map | ✅ HAVE | description, prompt, tools, model |
| System prompt override | `systemPrompt` | `system_prompt` | `:system_prompt` | ✅ HAVE | |
| System prompt preset | `systemPrompt.preset` | `SystemPromptPreset` | N/A | ⏸️ LATER | P3 - `claude_code` preset |

---

## Thinking & Extended Context

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Max thinking tokens | `maxThinkingTokens` | N/A | `:max_thinking_tokens` | ⏸️ LATER | P2 - Extended thinking |
| Beta features | `betas` | N/A | `:betas` | ⏸️ LATER | P2 - Beta enablement |
| Structured outputs | `outputFormat` | `output_format` | `:output_format` | ⏸️ LATER | P2 - JSON schema outputs |

---

## Query Methods (Runtime Control)

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Interrupt query | `interrupt()` | `interrupt()` | N/A | ⏸️ LATER | P2 - Streaming input only |
| Rewind files | `rewindFiles()` | `rewind_files()` | N/A | ⏸️ LATER | P3 - File checkpointing |
| Set permission mode | `setPermissionMode()` | N/A | N/A | ⏸️ LATER | P3 - Streaming input only |
| Set model | `setModel()` | N/A | N/A | ⏸️ LATER | P3 - Streaming input only |
| Set max thinking | `setMaxThinkingTokens()` | N/A | N/A | ⏸️ LATER | P3 - Streaming input only |
| Get supported commands | `supportedCommands()` | N/A | N/A | ⏸️ LATER | P3 - Slash command discovery |
| Get supported models | `supportedModels()` | N/A | N/A | ⏸️ LATER | P3 - Model discovery |
| Get account info | `accountInfo()` | N/A | N/A | ⏸️ LATER | P3 - Account information |
| Get session ID | N/A | (via ResultMessage) | `get_session_id/1` | ✅ HAVE | |
| Clear session | N/A | N/A | `clear/1` | ✅ HAVE | Elixir-specific |
| Connect/disconnect | N/A | `connect()`/`disconnect()` | `start_link()`/`stop()` | ✅ HAVE | Session lifecycle |

---

## Hooks & Plugins

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Event hooks | `hooks` | `hooks` | N/A | ⏸️ LATER | P2 - PreToolUse, PostToolUse, etc. |
| PreToolUse hook | ✅ | ✅ | N/A | ⏸️ LATER | Before tool execution |
| PostToolUse hook | ✅ | ✅ | N/A | ⏸️ LATER | After tool execution |
| UserPromptSubmit hook | ✅ | ✅ | N/A | ⏸️ LATER | On prompt submission |
| Stop hook | ✅ | ✅ | N/A | ⏸️ LATER | On execution stop |
| SubagentStop hook | ✅ | ✅ | N/A | ⏸️ LATER | On subagent stop |
| PreCompact hook | ✅ | ✅ | N/A | ⏸️ LATER | Before message compaction |
| SessionStart hook | ✅ | ❌ | N/A | ⏸️ LATER | Python doesn't support |
| SessionEnd hook | ✅ | ❌ | N/A | ⏸️ LATER | Python doesn't support |
| Notification hook | ✅ | ❌ | N/A | ⏸️ LATER | Python doesn't support |
| Plugins | `plugins` | `plugins` | N/A | ⏸️ LATER | P3 - Local plugin loading |
| File checkpointing | `enableFileCheckpointing` | `enable_file_checkpointing` | N/A | ⏸️ LATER | P3 - For file rewinding |

---

## Sandbox & Security

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| Sandbox enabled | `sandbox.enabled` | `sandbox.enabled` | N/A | ⏸️ LATER | P3 - Command sandboxing |
| Auto-allow sandboxed | `sandbox.autoAllowBashIfSandboxed` | `sandbox.autoAllowBashIfSandboxed` | N/A | ⏸️ LATER | P3 |
| Excluded commands | `sandbox.excludedCommands` | `sandbox.excludedCommands` | N/A | ⏸️ LATER | P3 |
| Allow unsandboxed | N/A | `sandbox.allowUnsandboxedCommands` | N/A | ⏸️ LATER | P3 |
| Network sandbox | `sandbox.network` | `sandbox.network` | N/A | ⏸️ LATER | P3 |
| Ignore violations | N/A | `sandbox.ignoreViolations` | N/A | ⏸️ LATER | P3 |
| Weaker nested sandbox | N/A | `sandbox.enableWeakerNestedSandbox` | N/A | ⏸️ LATER | P3 |

---

## Development Tools

| Feature | TS SDK | Python SDK | Elixir SDK | Status | Notes |
|---------|--------|------------|------------|--------|-------|
| CLI validation | N/A | (implicit) | `CLI.validate_installation/0` | ✅ HAVE | Health checks |
| Custom CLI path | `pathToClaudeCodeExecutable` | N/A | N/A | ⏸️ LATER | P3 - Use system PATH |
| Stderr callback | `stderr` | `stderr` | N/A | ⏸️ LATER | P3 - Stderr handling |
| Extra CLI args | `extraArgs` | `extra_args` | N/A | ⏸️ LATER | P3 - Pass-through args |
| Abort controller | `abortController` | N/A | N/A | ⏸️ LATER | P3 - Cancellation |
| Max buffer size | N/A | `max_buffer_size` | N/A | ⏸️ LATER | P3 - CLI stdout buffering |
| Environment variables | `env` | `env` | N/A | 🗑️ KILLED | Use OS environment |

---

## Runtime-Specific (Not Applicable to Elixir)

| Feature | TS SDK | Python SDK | Status | Notes |
|---------|--------|------------|--------|-------|
| JS runtime selection | `executable` | N/A | 🗑️ KILLED | N/A - Elixir runs on BEAM |
| Runtime args | `executableArgs` | N/A | 🗑️ KILLED | N/A - Elixir runs on BEAM |
| Debug mode | N/A | `debug_stderr` (deprecated) | 🗑️ KILLED | Use Elixir Logger |
| MCP debug | N/A | N/A | 🗑️ KILLED | Deprecated in CLI |
| IDE mode | N/A | N/A | 🗑️ KILLED | Interactive only |

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
| Custom tools (`@tool`) | In-process tool definitions |
| In-process MCP server | SDK-managed MCP servers |

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
| `systemPrompt.preset` | Preset system prompts |

---

## Competitive Analysis

### SDK Comparison Matrix

| Capability | TypeScript | Python | Elixir (Now) | Elixir (v1.0) | Elixir (v1.1+) |
|------------|-----------|--------|--------------|---------------|----------------|
| Model selection | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tool control | ✅ | ✅ | ✅ | ✅ | ✅ |
| Session management | ✅ | ✅ | ✅ | ✅ | ✅ |
| Streaming output | ✅ | ✅ | ✅ | ✅ | ✅ |
| Partial messages | ✅ | ✅ | ✅ | ✅ | ✅ |
| Custom agents | ✅ | ✅ | ✅ | ✅ | ✅ |
| Team settings | ✅ | ✅ | ✅ | ✅ | ✅ |
| MCP servers | ✅ | ✅ | ✅ | ✅ | ✅ |
| Permission modes | ✅ | ✅ | ✅ | ✅ | ✅ |
| Permission handler | ✅ | ✅ | ✅ | ✅ | ✅ |
| Fallback model | ✅ | ❌ | ❌ | ✅ | ✅ |
| Session forking | ✅ | ✅ | ❌ | ✅ | ✅ |
| Budget limiting | ✅ | ❌ | ❌ | ❌ | ✅ |
| Thinking tokens | ✅ | ❌ | ❌ | ❌ | ✅ |
| Structured outputs | ✅ | ✅ | ❌ | ❌ | ✅ |
| Hooks | ✅ | ✅ | ❌ | ❌ | ✅ |
| Sandbox | ✅ | ✅ | ❌ | ❌ | ✅ |
| Streaming input | ✅ | ✅ | ❌ | ❌ | ⏸️ |
| Custom tools (`@tool`) | ❌ | ✅ | ❌ | ❌ | ⏸️ |
| In-process MCP server | ❌ | ✅ | ✅* | ✅* | ✅* |
| File checkpointing | ✅ | ✅ | ❌ | ❌ | ⏸️ |
| Interrupt support | ✅ | ✅ | ❌ | ❌ | ⏸️ |

*Elixir uses Hermes MCP modules natively

### Key Architectural Differences

| Aspect | TypeScript | Python | Elixir |
|--------|-----------|--------|--------|
| Session model | Class-based | `query()` + `ClaudeSDKClient` | GenServer process |
| Concurrency | Async/await | Async/await | OTP supervision |
| MCP integration | Stdio/SSE/HTTP | Stdio/SSE/HTTP/SDK | Stdio/Hermes modules |
| Tool permissions | Function callback | Async callback | Module behaviour |
| Streaming | AsyncIterator | AsyncIterator | Elixir Stream |
| Process lifecycle | Manual | Context manager | OTP lifecycle |
| Error handling | Exceptions | Exceptions | Tagged tuples + OTP |

### Python SDK Unique Features

| Feature | Description | Elixir Alternative |
|---------|-------------|-------------------|
| `@tool` decorator | Type-safe tool definitions | Use MCP config/Hermes |
| `create_sdk_mcp_server()` | In-process MCP server | Hermes modules |
| `ClaudeSDKClient` context manager | `async with` cleanup | GenServer supervision |
| `AsyncIterable` input | Streaming prompts | Not planned |
| `ThinkingBlock` content | Extended thinking | Not yet supported |

### TypeScript SDK Unique Features

| Feature | Description | Elixir Alternative |
|---------|-------------|-------------------|
| `AbortController` | Cancellation | Process termination |
| `AsyncIterable` input | Streaming prompts | Not planned |
| Runtime setters | setModel, setPermissionMode | Restart session |

---

## Elixir-Specific Features (Not in TypeScript or Python)

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
| OTP supervision | Supervisor child spec | ✅ HAVE | Fault-tolerant sessions |

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

SDK Parity:
  vs TypeScript: Core 92% → 100% at v1.0, Full ~65% → ~90% at v1.1
  vs Python:     Core 92% → 100% at v1.0, Full ~70% → ~90% at v1.1
```

---

## Message Types Supported

| Type | TS SDK | Python SDK | Elixir SDK | Notes |
|------|--------|------------|------------|-------|
| System | ✅ | `SystemMessage` | `Message.System` | Init/metadata |
| Assistant | ✅ | `AssistantMessage` | `Message.Assistant` | Responses |
| User | ✅ | `UserMessage` | `Message.User` | Input/tool results |
| Result | ✅ | `ResultMessage` | `Message.Result` | Final response |
| StreamEvent | ✅ | (partial messages) | `StreamEvent` | Partial updates |

---

## Content Block Types Supported

| Type | TS SDK | Python SDK | Elixir SDK | Notes |
|------|--------|------------|------------|-------|
| Text | ✅ | `TextBlock` | `Content.Text` | Text content |
| ToolUse | ✅ | `ToolUseBlock` | `Content.ToolUse` | Tool invocations |
| ToolResult | ✅ | `ToolResultBlock` | `Content.ToolResult` | Tool results |
| Thinking | ✅ | `ThinkingBlock` | ❌ | Extended thinking |

---

**Last Updated**: 2025-12-29
**Reference**: TypeScript SDK v1 & Python SDK Documentation
**Next Action**: Add fallback model and session forking support
