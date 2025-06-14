# Phase 2 Implementation Findings

## CLI Output Analysis Summary

Based on the captured Claude CLI outputs, here are the key findings that will guide Phase 2 implementation.

## Message Types

### 1. System Messages
```json
{
  "type": "system",
  "subtype": "init",
  "details": {
    "sessionId": "...",
    "workingDirectory": "...",
    "availableTools": [...],
    "mcpServersConnected": [...],
    "model": "claude-3-5-sonnet-20241022",
    "permissionMode": "default",
    "apiKeySource": "environment"
  }
}
```

### 2. Assistant Messages
```json
{
  "type": "assistant",
  "assistant": {
    "id": "msg_...",
    "type": "message",
    "role": "assistant",
    "model": "claude-3-5-sonnet-20241022",
    "content": [
      {
        "type": "text",
        "text": "I'll help you..."
      },
      {
        "type": "tool_use",
        "id": "toolu_...",
        "name": "Read",
        "input": {
          "file_path": "README.md"
        }
      }
    ],
    "usage": {
      "input_tokens": 123,
      "output_tokens": 456,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 0
    },
    "stop_reason": "tool_use"
  }
}
```

### 3. User Messages (Tool Results)
```json
{
  "type": "user",
  "user": {
    "type": "message",
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_...",
        "content": "File contents here...",
        "is_error": false
      }
    ]
  }
}
```

### 4. Result Messages
```json
{
  "type": "result",
  "result": {
    "success": true,
    "duration": {
      "response": 2.5,
      "total": 3.1
    },
    "result": "The final response text...",
    "cost": {
      "inputTokens": 1234,
      "outputTokens": 567,
      "inputCost": "$0.0037",
      "outputCost": "$0.0085",
      "totalCost": "$0.0122"
    }
  }
}
```

## Content Block Types

### 1. Text Block
```json
{
  "type": "text",
  "text": "The actual text content"
}
```

### 2. Tool Use Block
```json
{
  "type": "tool_use",
  "id": "toolu_uniqueid",
  "name": "ToolName",
  "input": {
    "param1": "value1",
    "param2": "value2"
  }
}
```

### 3. Tool Result Block
```json
{
  "type": "tool_result",
  "tool_use_id": "toolu_uniqueid",
  "content": "Result content or error message",
  "is_error": false
}
```

## Permission System

The CLI has multiple permission modes:
- **`default`** - Requires manual approval for destructive operations
- **`auto-accept-all`** - Automatically approves all tool usage
- **`auto-accept-reads`** - Automatically approves read-only operations
- **`auto-reject-all`** - Rejects all tool usage

Permission denials appear as error messages:
```
"Claude requested permissions to use Write, but you haven't granted it yet."
```

## Tool Usage Flow

1. **Simple Query (No Tools)**
   ```
   System (init) → Assistant (text only) → Result
   ```

2. **Tool Usage Flow**
   ```
   System (init) → Assistant (text + tool_use) → User (tool_result) → Assistant (text) → Result
   ```

3. **Permission Denial Flow**
   ```
   System (init) → Assistant (text + tool_use) → User (permission error) → Assistant (alternative approach) → Result
   ```

4. **Complex Tool Chain**
   ```
   System → Assistant (tool1) → User (result1) → Assistant (tool2) → User (result2) → ... → Result
   ```

## Implementation Requirements

### Phase 2 Must Handle:

1. **Message Type Classes**
   - `SystemMessage` with subtype and details
   - `AssistantMessage` with content blocks and usage stats
   - `UserMessage` with tool results
   - `ResultMessage` with success/error and cost info

2. **Content Block Classes**
   - `TextBlock` for plain text
   - `ToolUseBlock` with tool name and inputs
   - `ToolResultBlock` with results and error flag

3. **Parsing Logic**
   - Detect message type from JSON
   - Parse nested content arrays
   - Handle mixed content (text + tools)
   - Preserve all metadata (IDs, usage, etc.)

4. **Pattern Matching Support**
   ```elixir
   case message do
     %AssistantMessage{content: [%TextBlock{}, %ToolUseBlock{name: "Read"}]} ->
       # Handle read operation
     %UserMessage{content: [%ToolResultBlock{is_error: true}]} ->
       # Handle error
   end
   ```

5. **Permission Awareness**
   - Parse permission mode from system message
   - Detect permission denial messages
   - Allow configuration of permission mode

## Test Fixtures Available

The following test fixtures are now available in `test/fixtures/cli_messages/`:
- `simple_hello.json` - Basic text response
- `math_calculation.json` - Computational response
- `file_listing.json` - Successful tool use (LS)
- `read_file.json` - File reading with tool
- `create_file.json` - Permission denial example
- `error_case.json` - Error handling with retries
- `permission_*` - Various permission mode tests
- `complex_tool_chain.json` - Multi-tool workflow

These provide real examples for TDD implementation of Phase 2.