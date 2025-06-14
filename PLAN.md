# Phase 2 Implementation Plan: Message Types & Content Blocks

## Overview

Phase 2 is **NOT implemented** despite the roadmap checkmarks. This plan outlines the complete implementation of message types and content blocks for the ClaudeCode Elixir SDK using Test-Driven Development (TDD).

## Core Principle: Test-Driven Development

**Every feature MUST be implemented using TDD:**
1. Write failing tests first
2. Implement minimal code to make tests pass
3. Refactor while keeping tests green
4. Each commit should include both tests and implementation

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

## 🔧 Detailed Implementation Steps (TDD Approach)

### 1. Research Phase (Do First!)
- [ ] Run real CLI commands with tool use
- [ ] Capture and analyze JSON output structure
- [ ] Document message formats and content block types
- [ ] Create test fixtures from real CLI output

### 2. Base Infrastructure (Tests First!)
```bash
# Step 1: Write failing tests
- [ ] Write test for message type detection
- [ ] Write test for content block type detection
- [ ] Run tests, verify they fail

# Step 2: Create directories
- [ ] Create `lib/claude_code/message/` directory
- [ ] Create `lib/claude_code/content/` directory
- [ ] Define shared behaviours/protocols

# Step 3: Make tests pass with minimal implementation
```

### 3. Message Types Implementation (TDD for each type)
For each message type:
```bash
# Example: AssistantMessage
- [ ] Write failing test for AssistantMessage.new/1
- [ ] Write failing test for AssistantMessage.to_json/1
- [ ] Write failing test for pattern matching
- [ ] Implement minimal AssistantMessage struct
- [ ] Implement new/1 to make test pass
- [ ] Implement to_json/1 to make test pass
- [ ] Add type guards and validation
- [ ] Refactor while keeping tests green
```

### 4. Content Blocks Implementation (TDD for each block)
For each content block:
```bash
# Example: TextBlock
- [ ] Write failing test for TextBlock.new/1
- [ ] Write failing test for content extraction
- [ ] Implement minimal TextBlock struct
- [ ] Implement parsing to make tests pass
- [ ] Add validation and error handling
- [ ] Refactor while keeping tests green
```

### 5. Integration Updates (Test existing behavior first)
```bash
# Step 1: Write integration tests for current behavior
- [ ] Test current Session message handling
- [ ] Document expected behavior changes

# Step 2: Update implementation incrementally
- [ ] Update `Session.handle_info/2` with tests
- [ ] Update `parse_message/1` with tests
- [ ] Update `extract_content/1` with tests
- [ ] Remove generic Message struct usage

# Step 3: Verify no regressions
- [ ] All existing tests still pass
- [ ] New integration tests pass
```

### 6. Comprehensive Test Suite
- [ ] Unit tests for each message type
- [ ] Unit tests for each content block type
- [ ] Integration tests with mock CLI responses
- [ ] Property-based tests for message parsing
- [ ] Real CLI integration tests (when available)
- [ ] Edge case tests (malformed JSON, missing fields)
- [ ] Performance tests for large messages

### 7. Documentation (Test examples!)
- [ ] Write doctests for each module
- [ ] Verify all code examples compile and run
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

## Implementation Order (TDD Workflow)

### Day 1: Research & Test Fixtures
1. **Morning**: Capture Real CLI Output
   - [ ] Run CLI with various commands
   - [ ] Capture tool use examples
   - [ ] Document JSON structures
   
2. **Afternoon**: Create Test Fixtures
   - [ ] Create `test/fixtures/cli_messages/` directory
   - [ ] Save real CLI outputs as fixture files
   - [ ] Write initial parsing tests using fixtures

### Day 2-3: Core Message Types (TDD)
For each message type:
1. **Write Tests First** (30 min per type)
   - [ ] Test file: `test/claude_code/message/[type]_test.exs`
   - [ ] Test construction, parsing, validation
   
2. **Implement to Pass** (45 min per type)
   - [ ] Create module: `lib/claude_code/message/[type].ex`
   - [ ] Make tests pass with minimal code
   
3. **Refactor** (15 min per type)
   - [ ] Improve code quality
   - [ ] Ensure all tests still pass

### Day 4-5: Content Blocks (TDD)
Same TDD cycle for each content block type

### Day 6-7: Integration (Incremental TDD)
1. **Test Current Behavior**
   - [ ] Write tests for existing Session behavior
   - [ ] Ensure we don't break working code
   
2. **Refactor Incrementally**
   - [ ] Update one method at a time
   - [ ] Run tests after each change
   - [ ] Commit working increments

### Day 8: Polish & Documentation
1. **Morning**: Performance & Edge Cases
   - [ ] Profile with large messages
   - [ ] Add missing edge case tests
   
2. **Afternoon**: Documentation
   - [ ] Write comprehensive docs
   - [ ] Add doctest examples
   - [ ] Update README

## TDD Commit Strategy

Each commit should follow this pattern:
```bash
# Example commit sequence for AssistantMessage
git add test/claude_code/message/assistant_message_test.exs
git commit -m "Add failing tests for AssistantMessage"

git add lib/claude_code/message/assistant_message.ex
git commit -m "Implement AssistantMessage to pass tests"

git add -u
git commit -m "Refactor AssistantMessage for clarity"
```

## Test Coverage Goals

- **Unit Test Coverage**: 100% for new code
- **Integration Test Coverage**: All happy paths + major error cases
- **Property Tests**: For all parsing functions
- **Doctest Coverage**: All public functions with examples

## TDD Guidelines & Best Practices

### Red-Green-Refactor Cycle
1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Improve code quality while keeping tests green

### Test Organization
```
test/
├── claude_code/
│   ├── message/
│   │   ├── assistant_message_test.exs
│   │   ├── user_message_test.exs
│   │   ├── tool_use_message_test.exs
│   │   └── result_message_test.exs
│   ├── content/
│   │   ├── text_block_test.exs
│   │   ├── tool_use_block_test.exs
│   │   └── tool_result_block_test.exs
│   └── session_integration_test.exs
└── fixtures/
    └── cli_messages/
        ├── simple_response.json
        ├── tool_use_response.json
        └── error_response.json
```

### Testing Checklist for Each Module
- [ ] Happy path tests
- [ ] Edge case tests (nil, empty, malformed input)
- [ ] Error handling tests
- [ ] Property-based tests for parsers
- [ ] Doctest for all public functions
- [ ] Integration test showing real usage

### Quality Gates
Before moving to next component:
- [ ] All tests pass (`mix test`)
- [ ] No compiler warnings (`mix compile --warnings-as-errors`)
- [ ] Credo passes (`mix credo --strict`)
- [ ] Dialyzer passes (`mix dialyzer`)
- [ ] Documentation complete (`mix docs`)
- [ ] Test coverage > 95% (`mix test --cover`)

## Notes

- The current implementation extracts only text content as strings
- Real CLI message structure needs to be verified before implementation
- Tool use is critical for Phase 2 - without it, many CLI features won't work
- Consider backward compatibility during the transition
- Each step should be independently testable and deployable