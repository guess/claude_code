# Upstream Source Files to Track

Key files in the upstream SDKs that drive changes in the Elixir SDK. Changes to these files
typically require corresponding updates. Organized by sync priority.

## TypeScript SDK (`@anthropic-ai/claude-agent-sdk`)

Source is **not public on GitHub** — types are distributed via npm as `.d.ts` files.
Fetched by `scripts/capture-cli-data.sh` from unpkg CDN.

| File | Captured As | What to Watch For | Elixir Modules Affected |
|---|---|---|---|
| `sdk.d.ts` | `ts-sdk-types.d.ts` | **Primary source for all sync checks** | — |
| ↳ `SDKMessage` union (~line 1922) | — | New message type variants | `message/`, `cli/parser.ex` |
| ↳ `Options` type (~line 697) | — | New session/query options | `options.ex`, `cli/command.ex` |
| ↳ `SDKControlRequestInner` union (~line 1758) | — | New control protocol operations | `cli/control.ex`, `cli/input.ex`, `adapter/port.ex` |
| ↳ `Query` interface (~line 1353) | — | New runtime control methods | `session.ex`, `session/server.ex` |
| ↳ `SDKControlInitializeResponse` | — | New init response fields | `adapter/port.ex`, `cli/control.ex` |
| ↳ Hook types (`HookEvent`, `HookInput`, etc.) | — | New hook events (currently 21) | `hook.ex` and related |
| ↳ Permission types (`CanUseTool`, etc.) | — | Permission callback changes | `options.ex`, `adapter/port.ex` |
| ↳ MCP types (`McpServerStatus`, etc.) | — | MCP config/status changes | `mcp/status.ex`, `options.ex` |
| ↳ `SDKSession` / V2 session API | — | New persistent session API (unstable) | Future: `session.ex` |
| `sdk-tools.d.ts` | *(not captured)* | Tool input/output schemas | Content blocks (if validating) |

## Anthropic API SDK (`@anthropic-ai/sdk`)

Content block types come from the Anthropic API, not the Agent SDK.
Fetched by `scripts/capture-cli-data.sh` from unpkg CDN.

| File | Captured As | What to Watch For | Elixir Modules Affected |
|---|---|---|---|
| `resources/beta/messages/messages.d.ts` | `anthropic-api-messages.d.ts` | **Content block types** | — |
| ↳ `BetaContentBlock` union | — | New content block types | `content/`, `cli/parser.ex` |
| ↳ `BetaRawContentBlockDelta` union | — | New delta types for streaming | `content.ex` (delta type) |
| ↳ `BetaRawMessageStreamEvent` | — | Streaming event structure changes | `cli/parser.ex` |

## Python SDK (`anthropics/claude-agent-sdk-python`)

Full source available on GitHub. Fetched by `scripts/capture-cli-data.sh` via `gh api`.

### Priority 1: Type Definitions & Options

| GitHub Path | Captured As | What to Watch For | Elixir Modules Affected |
|---|---|---|---|
| `src/claude_agent_sdk/types.py` | `python-sdk-types.py` | All types, options, MCP configs, hook types, permission types | `options.ex`, `message/`, `content/` |
| `src/claude_agent_sdk/_cli_version.py` | *(extracted to py-sdk-version.txt)* | Bundled CLI version baseline | `adapter/port/installer.ex` |

### Priority 2: Control Protocol & Parsing

| GitHub Path | Captured As | What to Watch For | Elixir Modules Affected |
|---|---|---|---|
| `src/claude_agent_sdk/_internal/query.py` | `python-sdk-query.py` | Control request/response handling, hook dispatch, can_use_tool routing, MCP message routing | `adapter/port.ex`, `cli/control.ex`, `cli/input.ex` |
| `src/claude_agent_sdk/_internal/message_parser.py` | `python-sdk-message-parser.py` | Message type dispatch, field extraction, new type handling | `cli/parser.ex` |
| `src/claude_agent_sdk/_internal/client.py` | `python-sdk-client.py` | Option validation, mutual exclusion rules, agent/hook preprocessing | `session/server.ex`, `options.ex` |

### Priority 3: CLI Flag Mapping & Transport

| GitHub Path | Captured As | What to Watch For | Elixir Modules Affected |
|---|---|---|---|
| `src/claude_agent_sdk/_internal/transport/subprocess_cli.py` | `python-sdk-subprocess-cli.py` | `_build_command()` flag mappings, binary resolution, env vars | `cli/command.ex`, `adapter/port/resolver.ex` |

### Priority 4: Public API Surface

| GitHub Path | Captured As | What to Watch For | Elixir Modules Affected |
|---|---|---|---|
| `src/claude_agent_sdk/client.py` | `python-sdk-public-client.py` | Public client methods (new runtime control, session management) | `session.ex` |
| `src/claude_agent_sdk/query.py` | *(not captured — thin wrapper)* | Public query function signature | `claude_code.ex` |
| `src/claude_agent_sdk/__init__.py` | *(not captured — exports only)* | New public exports indicating new features | Various |

### Priority 5: Feature Gap Tracking

| GitHub Path | Captured As | What to Watch For | Elixir Modules Affected |
|---|---|---|---|
| `src/claude_agent_sdk/_internal/sessions.py` | *(not captured)* | Session listing/history (not yet in Elixir SDK) | Future feature |
| `src/claude_agent_sdk/_internal/session_mutations.py` | *(not captured)* | Session rename/tag (not yet in Elixir SDK) | Future feature |
| `src/claude_agent_sdk/_errors.py` | *(not captured)* | Error type taxonomy | Error tuples |

## Cross-Reference: What Each Check Agent Needs

| Check Agent | Primary Captured Files | Secondary Files |
|---|---|---|
| **check-versions** | `cli-version.txt`, `bundled-version.txt`, `ts-sdk-version.txt`, `py-sdk-version.txt`, `anthropic-sdk-version.txt` | — |
| **check-message-types** | `ts-sdk-types.d.ts` (SDKMessage union), `python-sdk-types.py` (Message union) | `python-sdk-message-parser.py` |
| **check-content-blocks** | `anthropic-api-messages.d.ts` (BetaContentBlock union) | `ts-sdk-types.d.ts` |
| **check-control-protocol** | `ts-sdk-types.d.ts` (SDKControl* types), `python-sdk-query.py` (control handling) | `python-sdk-client.py` |
| **check-options** | `cli-help.txt`, `ts-sdk-types.d.ts` (Options type), `python-sdk-subprocess-cli.py` (_build_command), `python-sdk-types.py` (ClaudeAgentOptions) | `python-sdk-client.py` |
