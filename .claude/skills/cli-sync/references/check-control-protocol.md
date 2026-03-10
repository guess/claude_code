# Check Control Protocol Coverage

Self-contained instructions for detecting new, removed, or changed control protocol
message types — bidirectional JSON messages over stdin/stdout between SDK and CLI.

## Purpose

Detect drift in the control protocol layer: new request subtypes the CLI now
supports (or sends), removed subtypes, changed request/response shapes, and
missing public API accessors for initialize response data.

## Files to Read

### Captured data

- `captured/ts-sdk-types.d.ts` — search for all `SDKControl*` type definitions
  (request types, response types, and related interfaces)

### Elixir implementation

- `lib/claude_code/cli/control.ex` — outbound request builders (`*_request/N`),
  response builders (`success_response/2`, `error_response/2`), classification
  (`classify/1`), and response parsing (`parse_control_response/1`)
- `lib/claude_code/cli/control/types.ex` — type specs for control response maps
  (`set_servers_result`, `rewind_files_result`, `initialize_response`)
- `lib/claude_code/adapter/port.ex` — inbound request handling
  (`handle_inbound_control_request/2`), response dispatch
  (`handle_control_response/2`), cancel handling (`handle_control_cancel/2`),
  and `parse_initialize_response/1`
- `lib/claude_code/adapter/control_handler.ex` — callback implementations for
  `can_use_tool`, `hook_callback`, and `mcp_message` subtypes
- `lib/claude_code.ex` — public API functions that wrap control requests

### Current tracking

- `references/type-mapping.md` — the "Control Protocol Coverage" section
  documents the current status of every known control message type

### Git diff (for detecting new changes)

Run: `git diff HEAD -- .claude/skills/cli-sync/captured/ts-sdk-types.d.ts`

Filter the diff output for lines containing `SDKControl` to isolate control
protocol changes. Also check for new `Query` class methods that may indicate
new public accessors.

## Critical Rule: Never Fabricate Structures

**NEVER guess or infer field names, types, or structures for control protocol messages.** Only report fields that are explicitly present in the captured TS SDK type definitions or observed in actual Elixir source code. If a new control type is discovered but its field structure is unclear, flag it as "needs live validation" rather than inventing a plausible structure.

To validate new or unclear control types against real CLI output, use the SDK itself:

```elixir
# scripts/capture-control-data.exs — run via: mix run scripts/capture-control-data.exs
{:ok, session} = ClaudeCode.start_link(cli_path: :bundled)

# These return real parsed responses from the CLI
server_info = ClaudeCode.get_server_info(session)
models = ClaudeCode.supported_models(session)
agents = ClaudeCode.supported_agents(session)
commands = ClaudeCode.supported_commands(session)
account = ClaudeCode.account_info(session)
mcp_status = ClaudeCode.get_mcp_status(session)

# Write to captured/ for analysis
File.write!("captured/control-responses.json", Jason.encode!(server_info, pretty: true))

ClaudeCode.stop(session)
```

If new control request/response types are found, recommend creating a validation script before implementing structs.

## Analysis Steps

### 1. Outbound (SDK → CLI) Requests

1. Extract all `SDKControl*Request` type definitions from `ts-sdk-types.d.ts`.
   Look for interfaces/types matching the pattern `SDKControl\w+Request`.
2. For each request type, extract the `subtype` field value — this is the wire
   protocol identifier.
3. Check `control.ex` for a corresponding builder function (e.g.,
   `set_model_request/2` for subtype `"set_model"`).
4. Check `port.ex` `build_control_json/3` for a matching clause that dispatches
   to the builder.
5. Check `lib/claude_code.ex` for a public API function that exposes the request
   to consumers.
6. Categorize each request type:
   - **Implemented** — builder exists, wired through port.ex, public API present
   - **Skipped** — intentionally omitted (document reason: internal-only, no
     public TS method, etc.)
   - **Deferred** — no type definition in TS SDK yet (mentioned by name only)
   - **Missing** — type definition exists but no Elixir implementation

### 2. Inbound (CLI → SDK) Requests

1. Extract control request subtypes the CLI can send TO the SDK. In
   `port.ex`, find all `subtype` string matches in
   `handle_inbound_control_request/2` (both proxy and non-proxy paths).
2. Check `ts-sdk-types.d.ts` for corresponding type definitions (e.g.,
   `SDKControlPermissionRequest`, `SDKHookCallbackRequest`,
   `SDKControlElicitationRequest`).
3. Look for new inbound subtypes in the TS SDK that are not yet handled in
   `port.ex`.
4. Categorize each:
   - **Implemented** — fully handled with proper response
   - **Partial** — handled but with incomplete logic (e.g., logged and returns
     error)
   - **Missing** — present in TS SDK but no handling in port.ex

### 3. Response Parsing

1. Check `SDKControlInitializeResponse` fields in `ts-sdk-types.d.ts`.
2. Compare against `parse_initialize_response/1` in `port.ex` and the
   `initialize_response` type in `control/types.ex`.
3. Check for new response fields not yet extracted.
4. Check `ControlResponse` / `ControlErrorResponse` handling in
   `parse_control_response/1`.
5. Verify subtype-specific response parsing in `parse_control_result/2`
   (e.g., `:mcp_status`, `:set_mcp_servers`, `:rewind_files`).

### 4. Initialize Response Accessors

1. In `ts-sdk-types.d.ts`, find `Query` class methods that read from the cached
   initialize response (e.g., `supportedModels()`, `accountInfo()`,
   `supportedCommands()`, `supportedAgents()`, `initializationResult()`).
2. Check `lib/claude_code.ex` for corresponding public functions.
3. Report any TS accessor methods without an Elixir equivalent.

## Output Format

Return four tables matching the structure in `type-mapping.md` "Control Protocol
Coverage" section.

### SDK → CLI Requests

| TS SDK Type | TS Public Method | Elixir Builder | Elixir Public API | Status |
|---|---|---|---|---|

### CLI → SDK Requests

| TS SDK Type | Elixir Handling | Status |
|---|---|---|

### Response Parsing

| TS SDK Type | Elixir | Status |
|---|---|---|

### Initialize Response Accessors

| TS Public Method | Elixir Public API | Status |
|---|---|---|

Status values: **Implemented**, **Partial**, **Skipped**, **Deferred**, **Missing**

### New Types from Git Diff

List any `SDKControl*` types that appear in the git diff as additions (+lines)
but are not present in the current type-mapping.md tables. These represent
newly added control protocol types that need triage.

### Recommendations

For each Missing or Partial item, provide a brief recommendation:
- Which files need changes
- Whether a new public API function is warranted
- Whether the type can be safely Skipped (with justification)
