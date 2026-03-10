# Check Content Blocks

Self-contained instructions for detecting new, removed, or changed content block types by comparing Anthropic API types (from `@anthropic-ai/sdk`) and TS SDK content types against Elixir content module implementations.

## Purpose

Detect coverage gaps in the Elixir SDK's content block handling. Compare the canonical `BetaContentBlock` union and `BetaRawContentBlockDelta` union from the Anthropic API types against Elixir parser clauses and content modules to find missing, new, or changed types.

## Files to Read

### Captured data

- `captured/anthropic-api-messages.d.ts` -- Anthropic API types including `BetaContentBlock` variants, `BetaRawContentBlockDelta` variants, and `BetaRawContentBlockStartEvent` types. This is the canonical source for all content block types the API can return.
- `captured/ts-sdk-types.d.ts` -- May re-export or reference content block types. Check for any SDK-specific content wrappers or additional block types.

### Elixir implementation

- All files in `lib/claude_code/content/` -- One module per content block type.
- `lib/claude_code/cli/parser.ex` -- The `@content_parsers` module attribute defines the dispatch map from wire type string to Elixir struct module. Multiple wire types may map to a single module (e.g., all server tool result types map to `ServerToolResultBlock`).
- `lib/claude_code/content.ex` -- The `t()` type union, `content?/1` guard clauses, `parse_delta/1` function clauses, and `delta()` type spec.

### Current tracking

- `references/type-mapping.md` — the "Content Block Types" table documents the current mapping from Anthropic API types to Elixir content modules. Use as a baseline to identify what is already tracked vs newly discovered.

### Git diff for change detection

Run `git diff HEAD -- .claude/skills/cli-sync/captured/anthropic-api-messages.d.ts` to see what changed since the last capture. Focus on additions or removals in the `BetaContentBlock` and `BetaRawContentBlockDelta` unions.

## Critical Rule: Never Fabricate Structures

**NEVER guess or infer field names, types, or wire type values.** Only report what is explicitly present in the captured Anthropic API type definitions, TS SDK types, or Elixir source code. If a new content block type is discovered but its fields are unclear, flag it as "needs live validation" rather than inventing a structure.

## Analysis Steps

### 1. Extract the BetaContentBlock union

Locate the `BetaContentBlock` type alias in `anthropic-api-messages.d.ts`. List every member type name in the union. As of the current capture, this includes:

- `BetaTextBlock` (type: `"text"`)
- `BetaThinkingBlock` (type: `"thinking"`)
- `BetaRedactedThinkingBlock` (type: `"redacted_thinking"`)
- `BetaToolUseBlock` (type: `"tool_use"`)
- `BetaServerToolUseBlock` (type: `"server_tool_use"`)
- `BetaWebSearchToolResultBlock` (type: `"web_search_tool_result"`)
- `BetaWebFetchToolResultBlock` (type: `"web_fetch_tool_result"`)
- `BetaCodeExecutionToolResultBlock` (type: `"code_execution_tool_result"`)
- `BetaBashCodeExecutionToolResultBlock` (type: `"bash_code_execution_tool_result"`)
- `BetaTextEditorCodeExecutionToolResultBlock` (type: `"text_editor_code_execution_tool_result"`)
- `BetaToolSearchToolResultBlock` (type: `"tool_search_tool_result"`)
- `BetaMCPToolUseBlock` (type: `"mcp_tool_use"`)
- `BetaMCPToolResultBlock` (type: `"mcp_tool_result"`)
- `BetaContainerUploadBlock` (type: `"container_upload"`)
- `BetaCompactionBlock` (type: `"compaction"`)

For each member, find its interface definition and extract the `type` field's literal string value.

### 2. Extract the BetaRawContentBlockDelta union

Locate the `BetaRawContentBlockDelta` type alias. List every member and its `type` discriminator:

- `BetaTextDelta` (type: `"text_delta"`)
- `BetaInputJSONDelta` (type: `"input_json_delta"`)
- `BetaCitationsDelta` (type: `"citations_delta"`)
- `BetaThinkingDelta` (type: `"thinking_delta"`)
- `BetaSignatureDelta` (type: `"signature_delta"`)
- `BetaCompactionContentBlockDelta` (type: `"compaction_delta"`)

### 3. Match content blocks against Elixir parser

Read `lib/claude_code/cli/parser.ex` and extract all keys from the `@content_parsers` map. Each key is a wire type string mapping to an Elixir module's `new/1` function. Note that multiple API types may map to the same Elixir module -- the Elixir SDK uses a single `ServerToolResultBlock` for all server tool result variants (`web_search_tool_result`, `web_fetch_tool_result`, `code_execution_tool_result`, `bash_code_execution_tool_result`, `text_editor_code_execution_tool_result`, `tool_search_tool_result`).

Also check `lib/claude_code/content.ex` for:
- The `t()` type union -- verify it includes all implemented block types
- The `content?/1` clauses -- verify every struct has a matching clause
- The `content_type/1` clauses -- verify every struct has a matching clause

### 4. Match deltas against Elixir handling

Read the `parse_delta/1` function clauses in `lib/claude_code/content.ex`. Each clause pattern-matches on a `"type"` string. Also check the `delta()` type spec for completeness.

### 5. Categorize each type

Assign a status to each API type:

- **Implemented** -- A parser entry exists with a matching wire type string, and a dedicated Elixir struct module exists.
- **Mapped** -- The wire type is handled by a parser entry but maps to a shared/generic module (e.g., multiple server tool result types mapping to `ServerToolResultBlock`).
- **Missing** -- No parser entry exists. The block would be silently skipped (forward compatibility) or cause an `{:error, {:unknown_content_type, type}}`.
- **Partial** -- A struct module exists but is missing fields present in the API type definition.

### 6. Check git diff for newly added types

Examine `git diff HEAD -- .claude/skills/cli-sync/captured/anthropic-api-messages.d.ts`. Look for:

- New type names added to the `BetaContentBlock` union
- New type names added to the `BetaRawContentBlockDelta` union
- Removed types from either union
- New fields on existing block interfaces

### 7. Check for input-only block types

Some block types appear only in request params (e.g., `BetaImageBlockParam`, `BetaToolResultBlockParam`, `BetaDocumentBlock`/`BetaRequestDocumentBlock`). These are not part of the response `BetaContentBlock` union but may appear in user messages round-tripped through the CLI. Verify the parser handles these if they appear in `user_message.content` arrays. Check the `@content_parsers` map for entries like `"image"`, `"document"`, and `"tool_result"`.

## Output Format

Return two coverage tables:

### Content Blocks

| Anthropic API Type | Wire Type (`type` value) | Elixir Module | Status |
|---|---|---|---|

Status values: **Implemented**, **Mapped**, **Missing**, **Partial**

Use **Mapped** when a wire type routes to a shared module (e.g., `web_search_tool_result` to `ServerToolResultBlock`).

### Content Block Deltas

| Anthropic API Delta Type | Wire Type (`type` value) | Elixir Handling | Status |
|---|---|---|---|

For deltas, the "Elixir Handling" column references `Content.parse_delta/1` clauses.

### Summary

Report:

- **Total content block types** in `BetaContentBlock` union
- **Total delta types** in `BetaRawContentBlockDelta` union
- **Content blocks: Implemented / Mapped / Missing / Partial**
- **Deltas: Implemented / Missing**
- **New since last capture** -- types that appeared in the git diff
- **Removed since last capture** -- types that disappeared from either union
