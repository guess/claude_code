# Content Block Consolidation

Reduce 13 content block struct types to 8 by unifying tool use, tool result, and thinking variants into their parent structs. Variant modules become `@moduledoc false` internal parsers.

## Motivation

The current content block hierarchy has 13 public structs. Five of them (`MCPToolUseBlock`, `ServerToolUseBlock`, `MCPToolResultBlock`, `ServerToolResultBlock`, `RedactedThinkingBlock`) are structurally near-identical to their parent types, never pattern-matched on by consumers, and add cognitive overhead in documentation without providing meaningful differentiation.

The Anthropic API uses separate types because TypeScript discriminated unions require distinct type literals. In Elixir, a `:type` atom on a single struct serves the same purpose with less surface area.

## Design

### ToolUseBlock consolidation

`MCPToolUseBlock` and `ServerToolUseBlock` merge into `ToolUseBlock`. The `:type` field discriminates between the three origins:

```elixir
%ToolUseBlock{
  type: :tool_use | :server_tool_use | :mcp_tool_use,
  id: String.t(),
  name: String.t(),
  input: map(),
  caller: map() | nil,
  server_name: String.t() | nil
}
```

Field semantics:

- `name` — always a string. No atom conversion for server tool names. The upstream protocol uses strings; the SDK should not enumerate them.
- `caller` — invocation chain metadata. Present on `:tool_use` and `:server_tool_use`. Indicates who triggered this tool call (e.g., `%{"type" => "direct"}` or `%{"type" => "code_execution_20260120", "tool_id" => "toolu_abc"}`). `nil` for `:mcp_tool_use`.
- `server_name` — which MCP server provides this tool. Present only on `:mcp_tool_use`. `nil` for other types.
- `caller` and `server_name` are orthogonal: `caller` is about the call chain, `server_name` is about the tool's provider.

`String.Chars` implementation branches on `:type`:

- `:tool_use` — `"[tool: Read]"`
- `:server_tool_use` — `"[server tool: web_search]"`
- `:mcp_tool_use` — `"[mcp: my-server/tool-name]"`

### ToolResultBlock consolidation

`MCPToolResultBlock` and `ServerToolResultBlock` merge into `ToolResultBlock`. The three types mirror ToolUseBlock:

```elixir
%ToolResultBlock{
  type: :tool_result | :server_tool_result | :mcp_tool_result,
  tool_use_id: String.t(),
  content: String.t() | [Content.t()],
  is_error: boolean() | nil,
  caller: map() | nil
}
```

Field semantics:

- `is_error` — present on `:tool_result` and `:mcp_tool_result`. `nil` for `:server_tool_result`.
- `caller` — present on `:server_tool_result` only. `nil` for other types.
- The 6 upstream server tool result type strings (`web_search_tool_result`, `code_execution_tool_result`, `bash_code_execution_tool_result`, `text_editor_code_execution_tool_result`, `tool_search_tool_result`, `web_fetch_tool_result`) all collapse to `:server_tool_result`. The originating tool can be identified via `tool_use_id` matched to the corresponding `ToolUseBlock`.

`String.Chars` implementation branches on `:type`:

- `:tool_result` — content as string (current behavior)
- `:server_tool_result` — `"[server tool result]"`
- `:mcp_tool_result` — content as string or joined blocks (current behavior)

### ThinkingBlock consolidation

`RedactedThinkingBlock` merges into `ThinkingBlock`:

```elixir
%ThinkingBlock{
  type: :thinking | :redacted_thinking,
  thinking: String.t() | nil,
  signature: String.t() | nil,
  data: String.t() | nil
}
```

Field semantics:

- `:thinking` — `thinking` and `signature` are populated, `data` is `nil`.
- `:redacted_thinking` — `data` is the encrypted blob, `thinking` and `signature` are `nil`.

`String.Chars` branches on `:type`:

- `:thinking` — returns the `thinking` text
- `:redacted_thinking` — returns `"[redacted thinking]"`

`Stream.thinking_content/1` currently filters for `%ThinkingBlock{}` and extracts `.thinking`. After this change it will also receive redacted blocks. The fix: skip nil `thinking` values rather than filtering on type, so redacted blocks pass through the filter but produce no output.

```elixir
|> Enum.filter(&match?(%Content.ThinkingBlock{}, &1))
|> Enum.flat_map(fn
  %{thinking: thinking} when is_binary(thinking) -> [thinking]
  _ -> []
end)
```

### Unchanged content blocks

These retain their own structs — they are structurally distinct:

- `TextBlock`
- `ImageBlock`
- `DocumentBlock`
- `CompactionBlock`
- `ContainerUploadBlock`

### Variant module disposition

The 5 variant modules become `@moduledoc false` and stop defining structs:

| Module | Becomes |
|---|---|
| `Content.MCPToolUseBlock` | `@moduledoc false` parser, returns `%ToolUseBlock{type: :mcp_tool_use}` |
| `Content.ServerToolUseBlock` | `@moduledoc false` parser, returns `%ToolUseBlock{type: :server_tool_use}` |
| `Content.MCPToolResultBlock` | `@moduledoc false` parser, returns `%ToolResultBlock{type: :mcp_tool_result}` |
| `Content.ServerToolResultBlock` | `@moduledoc false` parser, returns `%ToolResultBlock{type: :server_tool_result}` |
| `Content.RedactedThinkingBlock` | `@moduledoc false` parser, returns `%ThinkingBlock{type: :redacted_thinking}` |

Each module:

- Removes `defstruct` and `@enforce_keys`
- Removes `use ClaudeCode.JSONEncoder`
- Removes `String.Chars` protocol implementation
- Keeps `new/1` function with existing validation logic, but constructs the parent struct
- Removes `@type t` (no longer a struct)

### Parser changes

`CLI.Parser` dispatch maps are unchanged — same keys, same module references. The `new/1` functions just return different struct types now.

### Content module changes

`Content` (`content.ex`):

- `Content.t()` union drops from 13 to 8 variants
- `content?/1` drops from 13 to 8 pattern match clauses
- `content_type/1` drops from 13 to 8 clauses

### JSONEncoder changes

- Variant modules remove `use ClaudeCode.JSONEncoder`
- Parent structs (`ToolUseBlock`, `ToolResultBlock`, `ThinkingBlock`) already have `use ClaudeCode.JSONEncoder`. Their `Jason.Encoder` implementation needs to handle encoding all `:type` variants correctly — specifically mapping the type atom back to the upstream string (e.g., `:mcp_tool_use` encodes as `"mcp_tool_use"`).

### Stream module changes

- `tool_uses/1` — `match?(%ToolUseBlock{}, &1)` now catches all tool use variants. This is more useful as a default.
- `tool_results_by_name/2` — `match?(%ToolResultBlock{}, &1)` catches all result variants.
- `collect/1` — same benefit.
- `thinking_content/1` — updated to skip nil thinking values (see ThinkingBlock section).
- No new functions needed. Users who need to filter to a specific variant match on `:type`.

### Test changes

- Variant module tests update assertions from `%MCPToolUseBlock{}` to `%ToolUseBlock{type: :mcp_tool_use}` etc.
- Parser tests update the same way.
- Stream tests gain coverage for the "catches all variants" behavior.
- Factory module updates if it builds variant structs.

### type-mapping.md changes

Update the content block table to reflect the consolidation. Variant modules are noted as `@moduledoc false` internal parsers with arrows to their parent struct. Example:

```
| `Content.MCPToolUseBlock` | `BetaMCPToolUseBlock` | -- | `@moduledoc false`; returns `%ToolUseBlock{type: :mcp_tool_use}` |
```

## Not in scope

- System message subtype consolidation (separate future effort)
- Changes to `ImageBlock`, `DocumentBlock`, `CompactionBlock`, `ContainerUploadBlock`
- Changes to message-level types (`AssistantMessage`, `UserMessage`, etc.)
