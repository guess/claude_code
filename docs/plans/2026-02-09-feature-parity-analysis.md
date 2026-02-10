# Feature Parity Analysis: Python SDK vs Elixir SDK

> Generated 2026-02-09 by comparing `anthropics/claude-code-sdk-python` v0.1.33 with `claude_code` Elixir SDK.

**Legend:**
- ✅ = Implemented
- ⚠️ = Partial (some aspects missing)
- ❌ = Not implemented
- — = Not applicable to this language/runtime

---

## 1. Public API Surface

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| One-shot query (auto session lifecycle) | ✅ `query()` | ✅ `ClaudeCode.query/2` | |
| Stateful interactive client | ✅ `ClaudeSDKClient` | ✅ `ClaudeCode.Session` GenServer | Different paradigms but equivalent |
| Async context manager | ✅ `async with` | — | Elixir uses GenServer start/stop |
| Stream response messages | ✅ async iterator | ✅ Elixir `Stream` | |
| SDK version accessor | ✅ `__version__` | ✅ `ClaudeCode.version/0` | |
| Health check | ❌ | ✅ `ClaudeCode.health/1` | Elixir-only |
| Process alive check | ❌ | ✅ `ClaudeCode.alive?/1` | Elixir-only |
| Get session ID | ✅ from ResultMessage | ✅ `ClaudeCode.get_session_id/1` | |
| Clear session | ❌ | ✅ `ClaudeCode.clear/1` | Elixir-only |
| Read conversation history | ❌ | ✅ `ClaudeCode.conversation/2` | Elixir-only (ClaudeCode.History) |
| Supervisor for multiple sessions | ❌ | ✅ `ClaudeCode.Supervisor` | Elixir-only OTP feature |

---

## 2. Session / Lifecycle Management

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Resume session by ID | ✅ `resume=` | ✅ `:resume` | |
| Fork session on resume | ✅ `fork_session=` | ✅ `:fork_session` | |
| Continue most recent conversation | ✅ `continue_conversation=` | ✅ `:continue` | |
| Session ID tracking | ✅ from messages | ✅ captured from messages | |
| Multi-turn persistent subprocess | ✅ | ✅ | Both keep CLI alive between queries |
| Query queuing (adapter busy) | ❌ | ✅ | Elixir queues when adapter not ready |
| Request timeout | ❌ | ✅ 300s default | Elixir has configurable timeout |
| Named sessions (process registry) | ❌ | ✅ `:name` option | OTP feature |

---

## 3. Options / Configuration

| Option | Python | Elixir | Notes |
|--------|--------|--------|-------|
| `model` | ✅ | ✅ | |
| `fallback_model` | ✅ | ✅ | |
| `system_prompt` (string override) | ✅ | ✅ | |
| `system_prompt` (preset with append) | ✅ `SystemPromptPreset` | ❌ | Python supports `{"type": "preset", "preset": "claude_code", "append": "..."}` |
| `append_system_prompt` | ✅ via preset | ✅ `:append_system_prompt` | Different API shapes |
| `max_turns` | ✅ | ✅ | |
| `max_budget_usd` | ✅ | ✅ | |
| `max_thinking_tokens` | ✅ | ✅ | |
| `permission_mode` | ✅ | ✅ | |
| `allowed_tools` | ✅ | ✅ | |
| `disallowed_tools` | ✅ | ✅ | |
| `tools` (base tool set / preset) | ✅ `ToolsPreset` | ✅ `:tools` | Python has preset type; Elixir has `:default`, `[]`, or list |
| `add_dirs` | ✅ | ✅ `:add_dir` | |
| `mcp_config` (file path) | ✅ | ✅ | |
| `mcp_servers` (map config) | ✅ | ✅ `:mcp_servers` | |
| `permission_prompt_tool` | ✅ | ✅ | |
| `output_format` (JSON schema) | ✅ | ✅ | |
| `settings` | ✅ | ✅ | |
| `setting_sources` | ✅ | ✅ | |
| `agents` (custom agents) | ✅ | ✅ | Both send via initialize handshake |
| `plugins` | ✅ | ✅ | |
| `include_partial_messages` | ✅ | ✅ | |
| `fork_session` | ✅ | ✅ | |
| `sandbox` | ✅ `SandboxSettings` | ✅ `:sandbox` map | Python has typed config; Elixir uses plain map |
| `betas` | ✅ | ✅ | |
| `env` (custom env vars) | ✅ | ✅ | |
| `cwd` (working directory) | ✅ | ✅ | |
| `cli_path` (custom binary) | ✅ | ✅ | |
| `enable_file_checkpointing` | ✅ | ✅ | |
| `api_key` | ✅ via env | ✅ `:api_key` option | |
| `extra_args` (arbitrary CLI flags) | ✅ | ✅ `:extra_args` | Appended at end of CLI args |
| `max_buffer_size` | ✅ 1MB default | ✅ `:max_buffer_size` | 1MB default, triggers `{:buffer_overflow, size}` |
| `stderr` callback | ✅ | ❌ | Callback for CLI stderr output |
| `debug_stderr` (deprecated) | ✅ | ❌ | Deprecated in Python |
| `user` (subprocess user) | ✅ | ❌ | Run CLI as different OS user |
| `can_use_tool` callback | ✅ | ✅ `:can_use_tool` | Module or function; auto-sets `--permission-prompt-tool stdio` |
| `hooks` (Python function hooks) | ✅ | ✅ `:hooks` | Map-based config with `ClaudeCode.Hook` behaviour; 9 event types |
| `timeout` | ❌ | ✅ `:timeout` | Elixir-specific |
| `tool_callback` | ❌ | ✅ | Elixir-specific post-execution callback |
| `adapter` | ❌ | ✅ | Elixir-specific pluggable adapter |
| `name` (process name) | ❌ | ✅ | OTP-specific |
| `session_id` (explicit) | ❌ | ✅ | |
| `file` (file resources) | ❌ | ✅ | |
| `from_pr` | ❌ | ✅ | |
| `debug` / `debug_file` | ❌ | ✅ | |
| `no_session_persistence` | ❌ | ✅ | |
| `disable_slash_commands` | ❌ | ✅ | |
| `allow_dangerously_skip_permissions` | ❌ | ✅ | |
| `strict_mcp_config` | ❌ | ✅ | |
| `input_format` | ❌ | ✅ | |

---

## 4. Control Protocol (Bidirectional SDK <-> CLI)

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Initialize handshake | ✅ `initialize` control request | ✅ `CLI.Control.initialize_request/3` | Both send agents via control protocol; Elixir also caches server_info |
| Interrupt generation | ✅ `client.interrupt()` | ✅ `ClaudeCode.interrupt/1` | Fire-and-forget via control protocol |
| Set permission mode dynamically | ✅ `client.set_permission_mode()` | ✅ `ClaudeCode.set_permission_mode/2` | Change mid-conversation |
| Set model dynamically | ✅ `client.set_model()` | ✅ `ClaudeCode.set_model/2` | Change mid-conversation |
| Rewind files | ✅ `client.rewind_files()` | ✅ `ClaudeCode.rewind_files/2` | Rewind to file checkpoint |
| Get MCP status | ✅ `client.get_mcp_status()` | ✅ `ClaudeCode.get_mcp_status/1` | Live MCP server status |
| Get server info | ✅ `client.get_server_info()` | ✅ `ClaudeCode.get_server_info/1` | Server initialization info |
| Control request/response routing | ✅ full bidirectional | ✅ `CLI.Control.classify/1` | Separate control channel from messages |
| Control request timeout | ✅ configurable | ✅ 30s default | |
| Control error responses | ✅ | ✅ | |

---

## 5. Tool Permission System

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| `can_use_tool` callback | ✅ | ✅ `:can_use_tool` | Module or function via `ClaudeCode.Hook` behaviour |
| PermissionResultAllow | ✅ with `updated_input`, `updated_permissions` | ✅ `{:allow, input}`, `{:allow, input, permissions: [...]}` | `Hook.Response` translates to wire format |
| PermissionResultDeny | ✅ with `message`, `interrupt` | ✅ `{:deny, reason}`, `{:deny, reason, interrupt: true}` | |
| PermissionUpdate types | ✅ 6 types | ✅ 6 types | addRules, replaceRules, removeRules, setMode, addDirectories, removeDirectories |
| PermissionRuleValue | ✅ | ✅ | Maps with `tool_name` + `rule_content` keys |
| Auto-set permission_prompt_tool="stdio" | ✅ | ✅ | Automatic when `:can_use_tool` is set |

---

## 6. Hook System

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| PreToolUse hooks | ✅ | ✅ | Before tool execution; can allow/deny/modify via `ClaudeCode.Hook` |
| PostToolUse hooks | ✅ | ✅ | After successful tool execution |
| PostToolUseFailure hooks | ✅ | ✅ | After failed tool execution |
| UserPromptSubmit hooks | ✅ | ✅ | When user submits prompt |
| Stop hooks | ✅ | ✅ | When agent stops |
| SubagentStop hooks | ✅ | ✅ | When subagent stops |
| SubagentStart hooks | ✅ | ✅ | When subagent starts |
| PreCompact hooks | ✅ | ✅ | Before context compaction |
| Notification hooks | ✅ | ✅ | Notification events |
| PermissionRequest hooks | ✅ | ❌ | Permission request events (not in CLI hook protocol) |
| HookMatcher (tool pattern matching) | ✅ | ✅ | Matcher strings in hooks config |
| Sync hook output | ✅ | ✅ | Immediate response via `Hook.Response` |
| Async hook output | ✅ | ❌ | Deferred with timeout (not supported) |
| Hook-specific output types | ✅ 8 types | ✅ 8 types | Per-event typed outputs via `Hook.Response` |

---

## 7. In-Process MCP Servers

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| `create_sdk_mcp_server()` | ✅ | ✅ `Tool.Server` macro | `use ClaudeCode.Tool.Server, name: "..."` with `tool` DSL blocks |
| `@tool` decorator | ✅ | ✅ `tool` macro | Different paradigm: Python uses decorators, Elixir uses compile-time DSL |
| SDK MCP server type | ✅ `McpSdkServerConfig` | ✅ `type: "sdk"` | Auto-detected via `Tool.Server.sdk_server?/1`, emitted in mcp-config |
| JSONRPC routing for SDK servers | ✅ | ✅ `MCP.Router` | Routes initialize, tools/list, tools/call via control protocol |
| Mixed SDK + external MCP servers | ✅ | ✅ | SDK servers routed in-process; external servers handled by CLI |
| Tool annotations support | ✅ | ❌ | MCP ToolAnnotations |
| Hermes module expansion | ❌ | ✅ | Elixir-only: auto-convert Elixir modules to stdio MCP |

---

## 8. Message Types

| Message Type | Python | Elixir | Notes |
|-------------|--------|--------|-------|
| SystemMessage | ✅ | ✅ | |
| AssistantMessage | ✅ | ✅ | |
| UserMessage | ✅ | ✅ | |
| ResultMessage | ✅ | ✅ | |
| StreamEvent / PartialAssistantMessage | ✅ `StreamEvent` | ✅ `PartialAssistantMessage` | Same data, different names |
| CompactBoundaryMessage | ❌ part of SystemMessage | ✅ separate type | Elixir splits this out |

---

## 9. Message Fields

| Field | Python | Elixir | Notes |
|-------|--------|--------|-------|
| **ResultMessage** | | | |
| `.result` | ✅ | ✅ | |
| `.is_error` | ✅ | ✅ | |
| `.subtype` | ✅ | ✅ | |
| `.duration_ms` | ✅ | ✅ | |
| `.duration_api_ms` | ✅ | ✅ | |
| `.num_turns` | ✅ | ✅ | |
| `.session_id` | ✅ | ✅ | |
| `.total_cost_usd` | ✅ | ✅ | |
| `.usage` | ✅ | ✅ | |
| `.structured_output` | ✅ | ✅ | |
| `.model_usage` | ❌ | ✅ | Per-model usage breakdown |
| `.permission_denials` | ❌ | ✅ | |
| `.stop_reason` | ❌ | ✅ | |
| `.errors` | ❌ | ✅ | |
| **AssistantMessage** | | | |
| `.content` (list of blocks) | ✅ | ✅ | |
| `.model` | ✅ | ✅ | |
| `.parent_tool_use_id` | ✅ | ✅ | |
| `.error` (API error type) | ✅ | ✅ | Both have error field |
| `.stop_reason` | ❌ | ✅ | |
| `.usage` | ❌ | ✅ | |
| `.context_management` | ❌ | ✅ | |
| **UserMessage** | | | |
| `.content` | ✅ | ✅ | |
| `.uuid` | ✅ | ✅ | |
| `.parent_tool_use_id` | ✅ | ✅ | |
| `.tool_use_result` | ✅ | ✅ | |
| **SystemMessage** | | | |
| `.subtype` | ✅ | ✅ | |
| `.data` (catch-all) | ✅ | ✅ | |
| `.session_id` | ✅ in data | ✅ direct field | |
| `.tools` | ✅ in data | ✅ direct field | Elixir parses into direct fields |
| `.model` | ✅ in data | ✅ direct field | |
| `.mcp_servers` | ✅ in data | ✅ direct field | |
| `.permission_mode` | ✅ in data | ✅ direct field | |
| `.claude_code_version` | ✅ in data | ✅ direct field | |
| `.slash_commands` | ✅ in data | ✅ direct field | |
| `.agents` | ✅ in data | ✅ direct field | |
| `.skills` | ✅ in data | ✅ direct field | |
| `.plugins` | ✅ in data | ✅ direct field | |

---

## 10. Content Block Types

| Type | Python | Elixir | Notes |
|------|--------|--------|-------|
| TextBlock | ✅ | ✅ | |
| ThinkingBlock | ✅ | ✅ | |
| ToolUseBlock | ✅ | ✅ | |
| ToolResultBlock | ✅ | ✅ | |

---

## 11. Stream Utilities

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Filter by message type | ❌ manual | ✅ `Stream.filter_type/2` | |
| Extract text content | ❌ manual | ✅ `Stream.text_content/1` | |
| Extract thinking content | ❌ manual | ✅ `Stream.thinking_content/1` | |
| Extract tool uses | ❌ manual | ✅ `Stream.tool_uses/1` | |
| Text deltas (partial streaming) | ❌ manual | ✅ `Stream.text_deltas/1` | |
| Thinking deltas | ❌ manual | ✅ `Stream.thinking_deltas/1` | |
| Content deltas | ❌ manual | ✅ `Stream.content_deltas/1` | |
| Buffered text | ❌ | ✅ `Stream.buffered_text/1` | |
| Collect to summary | ❌ | ✅ `Stream.collect/1` | |
| Until result | ❌ | ✅ `Stream.until_result/1` | |
| Tool results by name | ❌ | ✅ `Stream.tool_results_by_name/2` | |
| Filter event type | ❌ | ✅ `Stream.filter_event_type/2` | |
| Tap (side effects) | ❌ | ✅ `Stream.tap/2` | |
| On tool use callback | ❌ | ✅ `Stream.on_tool_use/2` | |
| Final text | ❌ | ✅ `Stream.final_text/1` | |

---

## 12. Transport / Adapter Layer

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Pluggable transport interface | ✅ `Transport` ABC | ✅ `Adapter` behaviour | Different names, similar concept |
| Default subprocess transport | ✅ `SubprocessCLITransport` | ✅ `Adapter.Local` | |
| Test/mock adapter | ❌ use Transport | ✅ `Adapter.Test` | Elixir has dedicated test adapter |
| Write serialization (lock) | ✅ `anyio.Lock` | ❌ | Prevents concurrent write races |
| JSON buffer overflow protection | ✅ `max_buffer_size` | ✅ `:max_buffer_size` | 1MB default limit |
| Stderr capture/callback | ✅ | ❌ | |
| User impersonation | ✅ `user` param | ❌ | |
| Eager adapter provisioning | ❌ | ✅ | Elixir starts adapter on init |
| Adapter status notifications | ❌ | ✅ | `:provisioning` -> `:ready` -> `{:error, _}` |
| Adapter health checks | ❌ | ✅ | `:healthy`, `:degraded`, `{:unhealthy, _}` |

---

## 13. CLI Binary Management

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Bundled binary in package | ✅ `_bundled/` | ✅ `priv/bin/` | |
| Auto-install on missing | ✅ bundled only | ✅ `:bundled` mode | |
| Version checking | ✅ warn if < 2.0.0 | ✅ exact version match | Elixir is stricter |
| Global binary discovery (PATH) | ✅ `shutil.which` | ✅ `:global` mode | |
| Common location search | ✅ hardcoded paths | ✅ `find_in_common_locations` | |
| Explicit path override | ✅ `cli_path=` | ✅ `:cli_path` | |
| Skip version check env var | ✅ `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK` | ❌ | |
| Install mix task | — | ✅ `mix claude_code.install` | |
| Uninstall mix task | — | ✅ `mix claude_code.uninstall` | |
| Path mix task | — | ✅ `mix claude_code.path` | |
| Validate installation | ❌ | ✅ `CLI.validate_installation/1` | |

---

## 14. Error Handling

| Error Type | Python | Elixir | Notes |
|-----------|--------|--------|-------|
| Base SDK error | ✅ `ClaudeSDKError` | ❌ uses tuples | Different paradigms |
| CLI not found | ✅ `CLINotFoundError` | ✅ `{:cli_not_found, msg}` | |
| CLI connection error | ✅ `CLIConnectionError` | ✅ `{:port_closed, _}` | |
| Process error (exit code) | ✅ `ProcessError` | ✅ `{:cli_exit, code}` | |
| JSON decode error | ✅ `CLIJSONDecodeError` | ✅ `{:json_decode_error, _, _}` | |
| Message parse error | ✅ `MessageParseError` | ✅ `{:parse_error, _, _}` | |
| Stream errors | ❌ exceptions | ✅ `{:stream_error, _}` | |
| Stream timeout | ❌ | ✅ `{:stream_timeout, _}` | |
| Provisioning failed | ❌ | ✅ `{:provisioning_failed, _}` | |
| Validation errors | ❌ | ✅ `NimbleOptions.ValidationError` | |

---

## 15. Conversation History

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Read session JSONL | ❌ | ✅ `History.read_session/2` | |
| Extract conversation | ❌ | ✅ `History.conversation/2` | |
| List sessions | ❌ | ✅ `History.list_sessions/2` | |
| List projects | ❌ | ✅ `History.list_projects/1` | |
| Session summary | ❌ | ✅ `History.summary/2` | |
| Project path encoding | ❌ | ✅ `History.encode_project_path/1` | |

---

## 16. Tool Callback

| Feature | Python | Elixir | Notes |
|---------|--------|--------|-------|
| Post-execution tool callback | ❌ | ✅ `:tool_callback` | Fires after tool result correlates with tool use |
| Tool use/result correlation | ❌ | ✅ `ToolCallback` module | Tracks pending tools |

---

## 17. Environment Variables Set by SDK

| Variable | Python | Elixir | Notes |
|----------|--------|--------|-------|
| `CLAUDE_CODE_ENTRYPOINT` | ✅ `sdk-py` / `sdk-py-client` | ✅ `sdk-ex` | |
| `CLAUDE_AGENT_SDK_VERSION` | ✅ | ✅ | |
| `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` | ✅ | ✅ | |
| `ANTHROPIC_API_KEY` | ✅ from env | ✅ from `:api_key` option | |
| `PWD` | ✅ from `cwd` | ❌ uses shell wrapper | Different approach to cwd |

---

## Summary: Major Gaps

### Features Python Has That Elixir Lacks

1. **`stderr` callback** - Capture CLI stderr output
2. **`user` impersonation** - Run subprocess as different OS user
3. **Write serialization lock** - Prevent concurrent write races
4. **System prompt preset** - `{"type": "preset", "preset": "claude_code", "append": "..."}` shape
5. **Async hook output** - Deferred hook responses with timeout
6. **PermissionRequest hooks** - Permission request event type
7. **MCP Tool annotations** - ToolAnnotations metadata on MCP tools

### Features Elixir Has That Python Lacks

1. **Stream Utilities** - Rich stream combinators (text_content, thinking_content, tool_uses, buffered_text, collect, etc.)
2. **Conversation History** - Read/list/search JSONL session files
3. **Supervisor** - OTP supervision tree for multiple sessions
4. **Health Checks** - Adapter health monitoring
5. **Tool Callback** - Post-execution tool use/result correlation
6. **Adapter Status Lifecycle** - Provisioning -> initializing -> ready -> error transitions
7. **Test Adapter** - Dedicated mock adapter for testing
8. **Named Sessions** - Process registry via OTP
9. **Query Queuing** - Queue queries when adapter busy
10. **Request Timeout** - Configurable per-request timeout
11. **Mix Tasks** - install, uninstall, path utilities
12. **Richer Message Parsing** - Direct struct fields for SystemMessage (vs Python's `data` dict)
13. **Richer ResultMessage** - model_usage, permission_denials, stop_reason, errors fields
14. **Validate Installation** - CLI binary validation function
15. **Optional Adapter Callbacks** - Control protocol support via `@optional_callbacks` for gradual adoption
