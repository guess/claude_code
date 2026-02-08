# Struct Definitions Reference

Complete field mappings for all message and content types in the ClaudeCode SDK.

## Message Types

### SystemMessage (`lib/claude_code/message/system_message.ex`)

Sent once at session start with initialization data.

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `:system` atom | Always "system" |
| `subtype` | `:subtype` | `:init` atom | Always "init" |
| `sessionId` | `:session_id` | string | UUID for session |
| `tools` | `:tools` | list of strings | Available tool names |
| `model` | `:model` | string | Model identifier |
| `permissionMode` | `:permission_mode` | atom | :default, :bypass_permissions, etc. |
| `apiKeySource` | `:api_key_source` | string | Source of API key |
| `maxThinkingTokens` | `:max_thinking_tokens` | integer or nil | Extended thinking limit |
| `mcpServers` | `:mcp_servers` | list of maps | MCP server configs |
| `customInstructions` | `:custom_instructions` | string or nil | System prompt additions |
| `claudeMdFiles` | `:claude_md_files` | list of strings | Loaded CLAUDE.md paths |
| `sessionType` | `:session_type` | atom | :sdk, :cli, etc. |
| `cwd` | `:cwd` | string | Working directory |
| `effectiveGitRoot` | `:effective_git_root` | string or nil | Git repository root |
| `environmentPlan` | `:environment_plan` | map | Plan configuration |
| `userType` | `:user_type` | atom | User tier |

### AssistantMessage (`lib/claude_code/message/assistant_message.ex`)

Claude's responses with content blocks.

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `:assistant` atom | Always "assistant" |
| `message` | `:message` | map | Nested message object |
| `message.content` | via `:message` | list | Content blocks |
| `message.context_management` | via `:message` | map or nil | Context management info |

**Important**: Access content via `message.message["content"]` or parse the nested structure.

### UserMessage (`lib/claude_code/message/user_message.ex`)

User input and tool results.

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `:user` atom | Always "user" |
| `message` | `:message` | map | Nested message object |
| `message.content` | via `:message` | list | Content blocks (text or tool_result) |

### ResultMessage (`lib/claude_code/message/result_message.ex`)

Final response after turn completion.

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `:result` atom | Always "result" |
| `result` | `:result` | string | Final response text |
| `isError` | `:is_error` | boolean | Error occurred flag |
| `subtype` | `:subtype` | atom or nil | :error_max_turns, :error_during_execution |
| `costUsd` | `:cost_usd` | float or nil | API cost |
| `inputTokens` | `:input_tokens` | integer or nil | Input token count |
| `outputTokens` | `:output_tokens` | integer or nil | Output token count |
| `totalTokens` | `:total_tokens` | integer or nil | Total token count |
| `duration_ms` | `:duration_ms` | integer or nil | Query duration |
| `sessionId` | `:session_id` | string or nil | Session identifier |
| `numTurns` | `:num_turns` | integer or nil | Number of turns taken |

### PartialAssistantMessage (`lib/claude_code/message/partial_assistant_message.ex`)

Streaming partial content (when `include_partial_messages: true`).

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `:partial_assistant` atom | Always "partial_assistant" |
| `content` | `:content` | list | Partial content blocks |
| `index` | `:index` | integer | Block index being updated |
| `delta` | `:delta` | map | The delta/change content |

### CompactBoundaryMessage (`lib/claude_code/message/compact_boundary_message.ex`)

Context compaction markers.

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `:compact_boundary` atom | Always "compact_boundary" |
| `direction` | `:direction` | atom | :start or :end |

## Content Block Types

### TextBlock (`lib/claude_code/content/text_block.ex`)

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `"text"` | Block type identifier |
| `text` | `:text` | string | Text content |

### ToolUseBlock (`lib/claude_code/content/tool_use_block.ex`)

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `"tool_use"` | Block type identifier |
| `id` | `:id` | string | Tool use ID for correlation |
| `name` | `:name` | string | Tool name (e.g., "Read", "Bash") |
| `input` | `:input` | map | Tool input parameters |

### ToolResultBlock (`lib/claude_code/content/tool_result_block.ex`)

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `"tool_result"` | Block type identifier |
| `tool_use_id` | `:tool_use_id` | string | Correlates to ToolUseBlock |
| `content` | `:content` | string or list | Tool output |
| `is_error` | `:is_error` | boolean | Tool error flag |

### ThinkingBlock (`lib/claude_code/content/thinking_block.ex`)

| JSON Key | Struct Field | Type | Notes |
|----------|--------------|------|-------|
| `type` | `:type` | `"thinking"` | Block type identifier |
| `thinking` | `:thinking` | string | Extended thinking content |
| `signature` | `:signature` | string | Thinking signature |

## Type Definitions (`lib/claude_code/types.ex`)

Common type definitions used across modules:

```elixir
@type message_type :: :system | :assistant | :user | :result | :partial_assistant | :compact_boundary
@type permission_mode :: :default | :accept_edits | :bypass_permissions | :delegate | :dont_ask | :plan
@type content_block :: TextBlock.t() | ToolUseBlock.t() | ToolResultBlock.t() | ThinkingBlock.t()
```

## Parsing Functions

Each struct module has a `from_json/1` function that handles:
- camelCase to snake_case conversion
- Type coercion (strings to atoms where needed)
- Optional field handling (defaults to nil)
- Nested structure parsing

Example pattern:

```elixir
def from_json(json) when is_map(json) do
  %__MODULE__{
    type: :the_type,
    field_name: json["camelCaseName"],
    optional_field: json["optionalField"]
  }
end
```

## Adding New Fields

When adding a new field:

1. Add to struct definition:
   ```elixir
   defstruct [..., :new_field]
   ```

2. Add to type spec:
   ```elixir
   @type t :: %__MODULE__{
     ...,
     new_field: String.t() | nil
   }
   ```

3. Add parsing in `from_json/1`:
   ```elixir
   new_field: json["newField"]
   ```

4. Add tests in corresponding test file

## Known Optional Fields

Fields that may not appear in all responses:

- `context_management` - Only in some assistant messages
- `cost_usd`, `*_tokens` - Only in result messages with usage tracking
- `mcp_servers` - Only when MCP is configured
- `custom_instructions` - Only when system prompt modified
- `signature` - Only in thinking blocks (extended thinking)

## Schema Comparison Patterns

### Identifying New Fields

When CLI JSON contains keys not in our structs:

```elixir
# CLI returns: {"inputTokens": 100, "outputTokens": 50}
# Our struct has: [:input_tokens]

# Action: Add :output_tokens field
defstruct [..., :output_tokens]

# Add parsing in from_json:
output_tokens: json["outputTokens"]
```

### Handling Nested Structures

Some fields contain nested objects:

```elixir
# CLI returns: {"context_management": {"mode": "auto", "tokens": 1000}}

# Add nested struct or map field:
context_management: json["context_management"]  # Keep as map
# or
context_management: ContextManagement.from_json(json["context_management"])
```

### Handling Optional Fields

New fields are often optional - check multiple CLI responses:

```elixir
# Field appears in some responses but not others
# Mark as optional with default nil:
defstruct [..., field_name: nil]
```
