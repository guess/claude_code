# Streaming vs Single Mode

Understanding the two input modes for the Claude Code Elixir SDK and when to use each.

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/streaming-vs-single-mode). Examples are adapted for Elixir.

---

## Overview

The Claude Code SDK supports two distinct input modes for interacting with agents:

- **Session-Based Streaming** (Default & Recommended) - A persistent, interactive session
- **Single-Shot Queries** - One-off queries that use session state and resuming

This guide explains the differences, benefits, and use cases for each mode to help you choose the right approach for your application.

## Session-Based Streaming (Recommended)

Session-based streaming is the **preferred** way to use the Claude Code SDK. It provides full access to the agent's capabilities and enables rich, interactive experiences.

It allows the agent to operate as a long-lived process that takes in user input, handles interruptions, surfaces permission requests, and handles session management.

### How It Works

```mermaid
sequenceDiagram
    participant App as Your Application
    participant Session as Claude Session
    participant Tools as Tools/Hooks
    participant FS as Environment/<br/>File System

    App->>Session: start_link(options)
    activate Session

    App->>Session: stream("Message 1")
    Session->>Tools: Execute tools
    Tools->>FS: Read files
    FS-->>Tools: File contents
    Tools->>FS: Write/Edit files
    FS-->>Tools: Success/Error
    Session-->>App: Stream partial response
    Session-->>App: Stream more content...
    Session->>App: Complete Message 1

    App->>Session: stream("Message 2")
    Session->>Tools: Process & execute
    Tools->>FS: Access filesystem
    FS-->>Tools: Operation results
    Session-->>App: Stream response 2

    App->>Session: stream("Message 3")
    App->>Session: Interrupt/Cancel
    Session->>App: Handle interruption

    Note over App,Session: Session stays alive
    Note over Tools,FS: Persistent file system<br/>state maintained

    deactivate Session
```

### Benefits

- **Tool Integration** - Full access to all tools and custom MCP servers during the session
- **Hooks Support** - Use lifecycle hooks to customize behavior at various points
- **Real-time Feedback** - See responses as they're generated, not just final results
- **Context Persistence** - Maintain conversation context across multiple turns naturally
- **Session Management** - Resume, continue, or fork previous conversations
- **Multi-turn Conversations** - Natural conversation flow with maintained context

### Implementation Example

```elixir
# Start a persistent session with tools
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Grep"]
)

# First message
session
|> ClaudeCode.stream("Analyze this codebase for security issues")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Wait for conditions or user input
Process.sleep(2000)

# Follow-up message - context is maintained
session
|> ClaudeCode.stream("Now check the authentication module specifically")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Clean shutdown
ClaudeCode.stop(session)
```

## Single-Shot Queries

Single-shot mode is simpler but more limited.

### When to Use Single-Shot Queries

Use single-shot queries when:

- You need a one-shot response
- You do not need hooks, real-time streaming, etc.
- You need to operate in a stateless environment, such as a serverless function

### Limitations

<div class="warning">

Single-shot mode does **not** support:
- Real-time streaming to your application (blocks until completion)
- Hook integration
- Natural multi-turn conversations (requires explicit session management)

**Note:** Image attachments are not currently supported by the SDK.

</div>

### Implementation Example

```elixir
# Simple one-shot query
result =
  ClaudeCode.query("Explain the authentication flow",
    allowed_tools: ["Read", "Grep"]
  )

case result do
  {:ok, response} -> IO.puts(response.result)
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end

# Continue conversation with session management
result =
  ClaudeCode.query("Now explain the authorization process",
    continue: true
  )

case result do
  {:ok, response} -> IO.puts(response.result)
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
```

## Next Steps

- [Streaming Output](streaming-output.md) - Character-level deltas and partial messages
- [Sessions](sessions.md) - Session management, resume, and forking
