# Check Message Types

Self-contained instructions for detecting new, removed, or changed message types by comparing the TS SDK's `SDKMessage` union against Elixir implementations.

## Purpose

Detect coverage gaps in the Elixir SDK's message type handling. Compare the canonical `SDKMessage` union from the TypeScript SDK against Elixir parser clauses and struct modules to find missing, new, or removed types.

## Files to Read

### Captured data

- `captured/ts-sdk-types.d.ts` -- Extract the `SDKMessage` union type and all member type definitions. This is the canonical source of truth for all message types the CLI can emit.
- `captured/python-sdk-types.py` -- Cross-reference the Python SDK's `Message` union (a subset of ~5 types). Useful for confirming wire type strings and field names.

### Elixir implementation

- All files in `lib/claude_code/message/` -- One module per top-level message type.
- All files in `lib/claude_code/message/system_message/` -- One module per system subtype.
- `lib/claude_code/cli/parser.ex` -- The `parse_message/1` function clauses define the complete dispatch table from wire JSON to Elixir structs.

### Current tracking

- `references/type-mapping.md` — the "Message Types" table documents the current mapping from TS/Python SDK types to Elixir message modules. Use as a baseline to identify what is already tracked vs newly discovered.

### Git diff for change detection

Run `git diff HEAD -- .claude/skills/cli-sync/captured/ts-sdk-types.d.ts` to see what changed in the TS SDK types since the last capture. Focus on additions or removals in the `SDKMessage` union and any new type definitions.

## Critical Rule: Never Fabricate Structures

**NEVER guess or infer field names, types, or wire type values.** Only report what is explicitly present in the captured TS SDK type definitions, Python SDK types, or Elixir source code. If a new message type is discovered but its structure is unclear, flag it as "needs live validation" rather than inventing fields.

## Analysis Steps

### 1. Extract the SDKMessage union

Locate the `SDKMessage` type alias in `ts-sdk-types.d.ts`. List every member type name in the union (e.g., `SDKSystemMessage`, `SDKAssistantMessage`, `SDKResultMessage`, etc.).

### 2. Map each member to its wire type

For each member type in the union, find its type definition and extract the `type` field's literal value. This is the wire type string that appears in the JSON the CLI emits (e.g., `"system"`, `"assistant"`, `"result"`).

For types with subtypes (like `SDKSystemMessage`), also extract the `subtype` field value.

### 3. Match against Elixir parser clauses

Read `lib/claude_code/cli/parser.ex` and list all `parse_message/1` function clause heads. Each clause pattern-matches on a `"type"` key (and optionally `"subtype"`). Build a mapping from wire type to Elixir module.

### 4. Categorize each type

Assign a status to each TS SDK member type:

- **Implemented** -- A dedicated Elixir struct module exists with a matching `parse_message/1` clause (e.g., `SDKAssistantMessage` maps to `Message.AssistantMessage`).
- **Catch-all** -- Handled by a parent module's catch-all clause. System subtypes routed through `SystemMessage` with subtype-specific modules under `SystemMessage.*` fall here if no dedicated clause exists.
- **Missing** -- No Elixir handling exists. The type would be silently dropped or cause an error.
- **Removed** -- Previously existed in the TS SDK but no longer appears in the current `SDKMessage` union.

### 5. Check git diff for new or removed types

Examine the output of `git diff HEAD -- .claude/skills/cli-sync/captured/ts-sdk-types.d.ts`. Look for:

- New type names added to the `SDKMessage` union
- Type names removed from the union
- Changed `type` or `subtype` literal values in existing definitions
- New fields on existing types (note these for field-level follow-up but do not report as type-level changes)

### 6. Cross-reference Python SDK

Read `captured/python-sdk-types.py` and extract the `Message` union members. Confirm that the wire type strings match between Python and TypeScript SDKs. Flag any discrepancies.

### 7. Check test and factory coverage

For each **Implemented** message type, verify:

- A test file exists at `test/claude_code/message/<type>_test.exs` (or under `system_message/` for subtypes)
- A factory function exists in `lib/claude_code/test/factory.ex` for creating test instances
- A message builder exists in `lib/claude_code/test.ex` if the type is commonly used in user-facing test stubs

Flag any **Implemented** types that are missing test files or factory functions. For **Missing** types that will be implemented, note that both a factory function and test file will be needed.

## Output Format

Return a coverage table:

| TS SDK Type | Wire Type (`type` value) | Elixir Module | Status |
|---|---|---|---|

Status values: **Implemented**, **Catch-all**, **Missing**, **Removed**

For system subtypes, include the subtype in the Wire Type column (e.g., `system/init`, `system/status`).

Also report:

- **Total types** in the `SDKMessage` union
- **Implemented** count (dedicated struct module)
- **Catch-all** count (handled by parent module)
- **Missing** count (no handling)
- **New since last capture** -- Any types that appeared in the git diff (list by name)
- **Removed since last capture** -- Any types that disappeared from the union
