# Phase 2 Implementation Plan: Message Types & Content Blocks

## Overview

Phase 2 is **NOT implemented** despite the roadmap checkmarks. This plan outlines the complete implementation of message types and content blocks for the ClaudeCode Elixir SDK.

## Current State

- ✅ Basic message handling (Phase 1)
- ❌ Message type modules
- ❌ Content block modules
- ❌ Tool use detection
- ❌ Pattern matching support

## 📋 High-Level Tasks

### 1. Message Type Modules (Priority: High)
- [ ] Create `assistant_message.ex` with struct and parsing
- [ ] Create `user_message.ex` with struct and validation
- [ ] Create `tool_use_message.ex` with tool invocation details
- [ ] Create `result_message.ex` for final results

### 2. Content Block Modules (Priority: High)
- [ ] Create `text_block.ex` for text content
- [ ] Create `tool_use_block.ex` for tool invocations
- [ ] Create `tool_result_block.ex` for tool results

### 3. Message Parsing Enhancement (Priority: High)
- [ ] Study real CLI output to understand message structures
- [ ] Parse content arrays instead of just extracting text
- [ ] Handle multiple content blocks per message

### 4. Pattern Matching Support (Priority: Medium)
- [ ] Add guards and pattern matching helpers
- [ ] Implement Enumerable protocol for message collections
- [ ] Add convenience functions for filtering by type

### 5. Tool Use Detection (Priority: High)
- [ ] Parse tool_use blocks from assistant messages
- [ ] Extract tool names and arguments
- [ ] Track tool invocation sequences

## 🔧 Detailed Implementation Steps

### 1. Research Phase (Do First!)
- [ ] Run real CLI commands with tool use
- [ ] Capture and analyze JSON output structure
- [ ] Document message formats and content block types

### 2. Base Infrastructure
- [ ] Create `lib/claude_code/message/` directory
- [ ] Create `lib/claude_code/content/` directory
- [ ] Define shared behaviours/protocols

### 3. Message Types Implementation
Each message type needs:
- [ ] Struct definition with proper fields
- [ ] `new/1` constructor from JSON
- [ ] `to_json/1` for serialization
- [ ] Type guards (`is_assistant_message/1`, etc.)
- [ ] Validation functions

### 4. Content Blocks Implementation
Each content block needs:
- [ ] Struct definition
- [ ] Parsing from JSON
- [ ] Type detection
- [ ] Content extraction methods

### 5. Integration Updates
- [ ] Update `Session.handle_info/2` to use new message types
- [ ] Update `parse_message/1` to detect and route to proper type
- [ ] Update `extract_content/1` to handle content blocks
- [ ] Remove generic Message struct usage

### 6. Testing Strategy
- [ ] Unit tests for each message type
- [ ] Unit tests for each content block type
- [ ] Integration tests with mock CLI responses
- [ ] Property-based tests for message parsing
- [ ] Real CLI integration tests (when available)

### 7. Documentation
- [ ] Document each message type with examples
- [ ] Document content block types
- [ ] Update main module docs
- [ ] Add usage examples to README

## 🚨 Critical Path Items

1. **MUST DO FIRST**: Run real CLI with tool use to capture actual JSON structure
2. **Blocking Issue**: Current parsing assumes simple text content - needs complete rewrite
3. **Risk**: Message structure assumptions may be wrong without real CLI testing

## 📝 Success Criteria

- [ ] Can parse all message types from CLI
- [ ] Can detect and extract tool use blocks
- [ ] Pattern matching works naturally in client code
- [ ] All tests pass with realistic CLI output
- [ ] Examples demonstrate all message types

## Example Usage (Target API)

```elixir
{:ok, messages} = ClaudeCode.query_sync(session, "Create a file named test.txt")

Enum.each(messages, fn
  %ClaudeCode.AssistantMessage{content: blocks} ->
    Enum.each(blocks, fn
      %ClaudeCode.TextBlock{text: text} ->
        IO.puts("Claude says: #{text}")
      %ClaudeCode.ToolUseBlock{name: tool, args: args} ->
        IO.puts("Claude wants to use tool: #{tool}")
    end)
  
  %ClaudeCode.ToolResultMessage{tool: tool, result: result} ->
    IO.puts("Tool #{tool} returned: #{result}")
    
  %ClaudeCode.ResultMessage{content: content} ->
    IO.puts("Final result: #{content}")
end)
```

## Implementation Order

1. **Research & Analysis** (Day 1)
   - Run CLI commands, capture outputs
   - Document JSON structures
   
2. **Core Message Types** (Day 2-3)
   - Implement message type modules
   - Basic parsing from JSON
   
3. **Content Blocks** (Day 4-5)
   - Implement content block types
   - Integrate with message types
   
4. **Integration & Testing** (Day 6-7)
   - Update Session to use new types
   - Comprehensive test suite
   
5. **Polish & Documentation** (Day 8)
   - Examples and documentation
   - Performance optimization

## Notes

- The current implementation extracts only text content as strings
- Real CLI message structure needs to be verified before implementation
- Tool use is critical for Phase 2 - without it, many CLI features won't work
- Consider backward compatibility during the transition