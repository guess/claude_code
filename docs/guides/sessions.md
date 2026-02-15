# Session Management

Understanding how the Claude Agent SDK handles sessions and session resumption.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/sessions). Examples are adapted for Elixir.

The Claude Agent SDK provides session management capabilities for handling conversation state and resumption. Sessions allow you to continue conversations across multiple interactions while maintaining full context.

## How Sessions Work

When you start a new query, the SDK automatically creates a session and returns a session ID in the initial system message. You can capture this ID to resume the session later.

```elixir
# Basic - uses ANTHROPIC_API_KEY from environment
{:ok, session} = ClaudeCode.start_link()

# With options
{:ok, session} = ClaudeCode.start_link(
  model: "sonnet",
  system_prompt: "You are an Elixir expert",
  timeout: 120_000
)

# Always stop when done
ClaudeCode.stop(session)
```

### Getting the Session ID

The session ID is available from the system init message or via `ClaudeCode.get_session_id/1`:

```elixir
{:ok, session} = ClaudeCode.start_link(model: "claude-opus-4-6")

# Send a query and capture the session ID from the system init message
session
|> ClaudeCode.stream("Help me build a web application")
|> Enum.each(fn
  %ClaudeCode.Message.SystemMessage{subtype: :init, session_id: id} ->
    IO.puts("Session started with ID: #{id}")
  _ ->
    :ok
end)

# Or retrieve it directly from the session GenServer
session_id = ClaudeCode.get_session_id(session)
# You can save this ID for later resumption
```

### Multi-Turn Conversations

Sessions automatically maintain conversation context across multiple queries:

```elixir
{:ok, session} = ClaudeCode.start_link()

session |> ClaudeCode.stream("My name is Alice") |> Stream.run()

response =
  session
  |> ClaudeCode.stream("What's my name?")
  |> ClaudeCode.Stream.final_text()
# => "Your name is Alice!"

ClaudeCode.stop(session)
```

## Resuming Sessions

The SDK supports resuming sessions from previous conversation states, enabling continuous development workflows. Use the `:resume` option with a session ID to continue a previous conversation:

```elixir
# Get the session ID after a conversation
{:ok, session} = ClaudeCode.start_link()
session |> ClaudeCode.stream("Remember: the code is 12345") |> Stream.run()
session_id = ClaudeCode.get_session_id(session)
ClaudeCode.stop(session)

# Later: resume with the same context
{:ok, session} = ClaudeCode.start_link(
  resume: session_id,
  model: "claude-opus-4-6",
  allowed_tools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash"]
)

response =
  session
  |> ClaudeCode.stream("What was the code?")
  |> ClaudeCode.Stream.final_text()
# => "The code is 12345"
```

The SDK automatically handles loading the conversation history and context when you resume a session, allowing Claude to continue exactly where it left off.

> **Tip:** To track and revert file changes across sessions, see [File Checkpointing](file-checkpointing.md).

### Continuing the Most Recent Conversation

Use `:continue` to automatically resume the last conversation in the current directory:

```elixir
{:ok, session} = ClaudeCode.start_link(continue: true)

session
|> ClaudeCode.stream("What were we talking about?")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

## Forking Sessions

When resuming a session, you can choose to either continue the original session or fork it into a new branch. By default, resuming continues the original session. Use the `:fork_session` option to create a new session ID that starts from the resumed state.

### When to Fork a Session

Forking is useful when you want to:

- Explore different approaches from the same starting point
- Create multiple conversation branches without modifying the original
- Test changes without affecting the original session history
- Maintain separate conversation paths for different experiments

### Forking vs Continuing

| Behavior | `fork_session: false` (default) | `fork_session: true` |
|----------|-------------------------------|---------------------|
| **Session ID** | Same as original | New session ID generated |
| **History** | Appends to original session | Creates new branch from resume point |
| **Original Session** | Modified | Preserved unchanged |
| **Use Case** | Continue linear conversation | Branch to explore alternatives |

### Example: Forking a Session

```elixir
# First, capture the session ID
{:ok, session} = ClaudeCode.start_link(model: "claude-opus-4-6")
session |> ClaudeCode.stream("Help me design a REST API") |> Stream.run()
session_id = ClaudeCode.get_session_id(session)

# Fork the session to try a different approach
{:ok, forked} = ClaudeCode.start_link(
  resume: session_id,
  fork_session: true,  # Creates a new session ID
  model: "claude-opus-4-6"
)

forked
|> ClaudeCode.stream("Now let's redesign this as a GraphQL API instead")
|> ClaudeCode.Stream.final_text()

# After first query, fork has a new session ID
forked_id = ClaudeCode.get_session_id(forked)
forked_id != session_id
# => true

# The original session remains unchanged and can still be resumed
{:ok, continued} = ClaudeCode.start_link(
  resume: session_id,
  fork_session: false,  # Continue original session (default)
  model: "claude-opus-4-6"
)

continued
|> ClaudeCode.stream("Add authentication to the REST API")
|> ClaudeCode.Stream.final_text()
```

## Clearing Context

Reset conversation history without stopping the session:

```elixir
ClaudeCode.clear(session)

# Next query starts fresh
session
|> ClaudeCode.stream("Hello!")
|> ClaudeCode.Stream.final_text()
```

## Reading Conversation History

Access past conversations stored in `~/.claude/projects/`:

```elixir
# By session ID
{:ok, messages} = ClaudeCode.conversation("abc123-def456")

Enum.each(messages, fn
  %ClaudeCode.Message.UserMessage{message: %{content: content}} ->
    IO.puts("User: #{inspect(content)}")
  %ClaudeCode.Message.AssistantMessage{message: %{content: blocks}} ->
    text = Enum.map_join(blocks, "", fn
      %ClaudeCode.Content.TextBlock{text: t} -> t
      _ -> ""
    end)
    IO.puts("Assistant: #{text}")
end)

# From a running session
{:ok, messages} = ClaudeCode.conversation(session)
```

## Named Sessions

Register sessions with atoms for easy access:

```elixir
{:ok, _} = ClaudeCode.start_link(name: :assistant)

# Use from anywhere in your app
:assistant
|> ClaudeCode.stream("Hello!")
|> ClaudeCode.Stream.final_text()
```

## Supervised Sessions

For production fault tolerance, use `ClaudeCode.Supervisor`:

```elixir
children = [
  {ClaudeCode.Supervisor, [
    [name: :assistant, system_prompt: "General helper"],
    [name: :code_reviewer, system_prompt: "You review Elixir code"]
  ]}
]

Supervisor.start_link(children, strategy: :one_for_one)

# Sessions restart automatically on crashes
:assistant |> ClaudeCode.stream("Hello!") |> Stream.run()
```

### Dynamic Session Management

```elixir
{:ok, supervisor} = ClaudeCode.Supervisor.start_link([])

# Add sessions on demand
ClaudeCode.Supervisor.start_session(supervisor, [
  name: :temp_session,
  system_prompt: "Temporary helper"
])

# Remove when done
ClaudeCode.Supervisor.terminate_session(supervisor, :temp_session)

# List active sessions
ClaudeCode.Supervisor.list_sessions(supervisor)
```

## Session Options Reference

| Option                   | Type    | Description                                             |
| ------------------------ | ------- | ------------------------------------------------------- |
| `name`                   | atom    | Register with a name for global access                  |
| `resume`                 | string  | Session ID to resume                                    |
| `continue`               | boolean | Continue the most recent conversation                   |
| `fork_session`           | boolean | Create new session ID when resuming (use with `resume`) |
| `session_id`             | string  | Use a specific session ID (must be a valid UUID)        |
| `no_session_persistence` | boolean | Don't save sessions to disk                             |
| `model`                  | string  | Claude model ("sonnet", "opus", etc.)                   |
| `system_prompt`          | string  | Override system prompt                                  |
| `timeout`                | integer | Query timeout in ms (default: 300,000)                  |

## Runtime Control

Change session settings mid-conversation without restarting:

```elixir
# Switch model mid-conversation
{:ok, _} = ClaudeCode.set_model(session, "claude-sonnet-4-5-20250929")

# Change permission mode
{:ok, _} = ClaudeCode.set_permission_mode(session, :bypass_permissions)

# Query MCP server status
{:ok, %{"servers" => servers}} = ClaudeCode.get_mcp_status(session)

# Rewind files to a checkpoint (requires enable_file_checkpointing: true)
{:ok, _} = ClaudeCode.rewind_files(session, "user-msg-uuid-123")

# Get server info from the initialize handshake
{:ok, info} = ClaudeCode.get_server_info(session)
```

These functions use the bidirectional control protocol to communicate with the CLI subprocess without interrupting the conversation flow.

## Session Lifecycle

| Event                | Behavior                                                      |
| -------------------- | ------------------------------------------------------------- |
| `start_link/1`       | Creates GenServer, CLI adapter starts eagerly                 |
| Adapter initializing | Sends initialize handshake, adapter status is `:provisioning` |
| Adapter ready        | Handshake complete, adapter status is `:ready`                |
| First query          | Sent to the already-running CLI subprocess                    |
| Subsequent queries   | Reuses existing CLI connection with session context           |
| `clear/1`            | Resets session ID, next query starts fresh                    |
| `stop/1`             | Terminates GenServer and CLI subprocess                       |
| Process crash        | Supervisor restarts if supervised                             |

## Next Steps

- [Streaming Output](streaming-output.md) - Real-time character-level streaming
- [Hosting](hosting.md) - Production deployment with OTP
- [File Checkpointing](file-checkpointing.md) - Track and revert file changes
