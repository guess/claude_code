# Phase 2: Complete Message Schema Documentation

Based on analysis of real Claude CLI output, this document defines the exact message schemas for Phase 2 implementation.

## Message Types

### 1. System Messages

```elixir
defmodule ClaudeCode.Message.System do
  @type t :: %__MODULE__{
    type: :system,
    subtype: :init,
    cwd: String.t(),
    session_id: String.t(),
    tools: [String.t()],
    mcp_servers: [mcp_server()],
    model: String.t(),
    permission_mode: :default | :bypass_permissions,
    api_key_source: String.t()
  }
  
  @type mcp_server :: %{
    name: String.t(),
    status: String.t()
  }
end
```

### 2. Assistant Messages

```elixir
defmodule ClaudeCode.Message.Assistant do
  @type t :: %__MODULE__{
    type: :assistant,
    message_id: String.t(),
    role: :assistant,
    model: String.t(),
    content: [ClaudeCode.Content.t()],
    stop_reason: nil | :tool_use | :end_turn | String.t(),
    stop_sequence: nil | String.t(),
    usage: usage_stats(),
    parent_tool_use_id: nil | String.t(),
    session_id: String.t()
  }
  
  @type usage_stats :: %{
    input_tokens: integer(),
    cache_creation_input_tokens: integer(),
    cache_read_input_tokens: integer(),
    output_tokens: integer(),
    service_tier: String.t()
  }
end
```

### 3. User Messages

```elixir
defmodule ClaudeCode.Message.User do
  @type t :: %__MODULE__{
    type: :user,
    role: :user,
    content: [ClaudeCode.Content.t()],
    parent_tool_use_id: nil | String.t(),
    session_id: String.t()
  }
end
```

### 4. Result Messages

```elixir
defmodule ClaudeCode.Message.Result do
  @type t :: %__MODULE__{
    type: :result,
    subtype: :success | :error,
    is_error: boolean(),
    duration_ms: integer(),
    duration_api_ms: integer(),
    num_turns: integer(),
    result: String.t(),
    session_id: String.t(),
    total_cost_usd: float(),
    usage: usage_summary()
  }
  
  @type usage_summary :: %{
    input_tokens: integer(),
    cache_creation_input_tokens: integer(),
    cache_read_input_tokens: integer(),
    output_tokens: integer(),
    server_tool_use: %{
      web_search_requests: integer()
    }
  }
end
```

## Content Block Types

### 1. Text Content

```elixir
defmodule ClaudeCode.Content.Text do
  @type t :: %__MODULE__{
    type: :text,
    text: String.t()
  }
end
```

### 2. Tool Use Content

```elixir
defmodule ClaudeCode.Content.ToolUse do
  @type t :: %__MODULE__{
    type: :tool_use,
    id: String.t(),
    name: String.t(),
    input: map()
  }
end
```

### 3. Tool Result Content

```elixir
defmodule ClaudeCode.Content.ToolResult do
  @type t :: %__MODULE__{
    type: :tool_result,
    tool_use_id: String.t(),
    content: String.t(),
    is_error: boolean() | nil
  }
end
```

## Message Flow Patterns

### Simple Query (No Tools)
```
System(init) → Assistant([Text]) → Result
```

### Tool Usage
```
System(init) → Assistant([Text]) → Assistant([ToolUse]) → User([ToolResult]) → Assistant([Text]) → Result
```

### Permission Denial
```
System(init) → Assistant([ToolUse]) → User([ToolResult{is_error: true}]) → Assistant([Text]) → Result
```

### Complex Tool Chain
```
System(init) → Assistant([ToolUse]) → User([ToolResult]) → Assistant([Text, ToolUse]) → User([ToolResult]) → ... → Result
```

## Parsing Rules

1. **Message Type Detection**
   - Check `"type"` field first
   - For assistant/user messages, nested structure under `"message"` key
   - System and result messages have flat structure

2. **Content Array Handling**
   - Always expect array, even for single items
   - Parse each content block based on its `"type"` field
   - Preserve order of content blocks

3. **Optional Fields**
   - `stop_reason`, `stop_sequence` can be nil
   - `parent_tool_use_id` usually nil except in tool chains
   - `is_error` in tool_result may be absent (treat as false)

4. **Permission Errors**
   - Look for specific text pattern in tool_result content
   - Always marked with `is_error: true`

## Example JSON Structures

### Assistant with Tool Use
```json
{
  "type": "assistant",
  "message": {
    "id": "msg_01ABC...",
    "type": "message",
    "role": "assistant",
    "model": "claude-opus-4-20250514",
    "content": [
      {
        "type": "text",
        "text": "I'll create that file for you."
      },
      {
        "type": "tool_use",
        "id": "toolu_01XYZ...",
        "name": "Write",
        "input": {
          "file_path": "/path/to/file.txt",
          "content": "File contents"
        }
      }
    ],
    "stop_reason": "tool_use",
    "usage": {...}
  },
  "session_id": "abc-123..."
}
```

### User with Tool Result
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_01XYZ...",
        "content": "File created successfully",
        "is_error": false
      }
    ]
  },
  "session_id": "abc-123..."
}
```

## Implementation Checklist

- [ ] Create base Message behaviour/protocol
- [ ] Implement System message parsing
- [ ] Implement Assistant message parsing
- [ ] Implement User message parsing
- [ ] Implement Result message parsing
- [ ] Create base Content behaviour/protocol
- [ ] Implement Text content parsing
- [ ] Implement ToolUse content parsing
- [ ] Implement ToolResult content parsing
- [ ] Add pattern matching helpers
- [ ] Update Session to use new types
- [ ] Write comprehensive tests for each type