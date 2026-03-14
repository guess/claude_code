# Session Management

How sessions persist agent conversation history, and when to use continue, resume, and fork to return to a prior run.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/sessions). Examples are adapted for Elixir.

A session is the conversation history the SDK accumulates while your agent works. It contains your prompt, every tool call the agent made, every tool result, and every response. The SDK writes it to disk automatically so you can return to it later.

Returning to a session means the agent has full context from before: files it already read, analysis it already performed, decisions it already made. You can ask a follow-up question, recover from an interruption, or branch off to try a different approach.

> **Note:** Sessions persist the **conversation**, not the filesystem. To snapshot and revert file changes the agent made, use [File Checkpointing](file-checkpointing.md).

This guide covers how to pick the right approach for your app, how sessions are tracked automatically, how to capture session IDs and use resume and fork manually, and what to know about resuming sessions across hosts.

## Choose an approach

How much session handling you need depends on your application's shape. Session management comes into play when you send multiple prompts that should share context. Within a single `ClaudeCode.query/2` call, the agent already takes as many turns as it needs, and permission prompts are handled in-loop (they don't end the call).

| What you're building | What to use |
|:---|:---|
| One-shot task: single prompt, no follow-up | Nothing extra. One `ClaudeCode.query/2` call handles it. |
| Multi-turn chat in one process | [Automatic session management](#automatic-session-management). The SDK tracks the session for you with no ID handling. |
| Pick up where you left off after a process restart | `continue: true`. Resumes the most recent session in the directory, no ID needed. |
| Resume a specific past session (not the most recent) | Capture the session ID and pass it to `:resume`. |
| Try an alternative approach without losing the original | Fork the session. |
| Stateless task, don't want anything written to disk | Set `no_session_persistence: true`. The session exists only in memory for the duration of the call. |

### Continue, resume, and fork

Continue, resume, and fork are option fields you set on `ClaudeCode.start_link/1`.

**Continue** and **resume** both pick up an existing session and add to it. The difference is how they find that session:

- **Continue** finds the most recent session in the current directory. You don't track anything. Works well when your app runs one conversation at a time.
- **Resume** takes a specific session ID. You track the ID. Required when you have multiple sessions (for example, one per user in a multi-user app) or want to return to one that isn't the most recent.

**Fork** is different: it creates a new session that starts with a copy of the original's history. The original stays unchanged. Use fork to try a different direction while keeping the option to go back.

## Automatic session management

The Elixir SDK's `ClaudeCode.Session` GenServer tracks session state for you across calls, so you don't pass IDs around manually. Each call to `ClaudeCode.stream/3` or `ClaudeCode.query/2` on the same session process automatically continues the same conversation.

This example runs two queries against the same session. The first asks the agent to analyze a module; the second asks it to refactor that module. Because both calls go through the same session process, the second query has full context from the first without any explicit resume or session ID:

```elixir
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Edit", "Glob", "Grep"]
)

# First query: session captures the session ID internally
session |> ClaudeCode.stream("Analyze the auth module") |> Stream.run()

# Second query: automatically continues the same session
response =
  session
  |> ClaudeCode.stream("Now refactor it to use JWT")
  |> ClaudeCode.Stream.final_text()

ClaudeCode.stop(session)
```

## Capture the session ID

Resume and fork require a session ID. The session ID is available from the system init message or via `ClaudeCode.Session.session_id/1`:

```elixir
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Read", "Glob", "Grep"]
)

# Send a query
session
|> ClaudeCode.stream("Analyze the auth module and suggest improvements")
|> ClaudeCode.Stream.final_text()

# Retrieve the session ID from the session GenServer
session_id = ClaudeCode.Session.session_id(session)
# You can save this ID for later resumption
```

You can also capture it from the stream by matching on the system init message:

```elixir
session
|> ClaudeCode.stream("Analyze the auth module")
|> Enum.each(fn
  %ClaudeCode.Message.SystemMessage{subtype: :init, session_id: id} ->
    # Store the session ID
    :ok
  _ ->
    :ok
end)
```

## Resume by ID

Pass a session ID to `:resume` to return to that specific session. The agent picks up with full context from wherever the session left off. Common reasons to resume:

- **Follow up on a completed task.** The agent already analyzed something; now you want it to act on that analysis without re-reading files.
- **Recover from a limit.** The first run ended with an `error_max_turns` result; resume with a higher limit.
- **Restart your process.** You captured the ID before shutdown and want to restore the conversation.

This example resumes a session with a follow-up prompt. Because you're resuming, the agent already has the prior analysis in context:

```elixir
# Earlier session analyzed the code; now build on that analysis
{:ok, session} = ClaudeCode.start_link(
  resume: session_id,
  allowed_tools: ["Read", "Edit", "Write", "Glob", "Grep"]
)

response =
  session
  |> ClaudeCode.stream("Now implement the refactoring you suggested")
  |> ClaudeCode.Stream.final_text()
```

> **Tip:** If a resume call returns a fresh session instead of the expected history, the most common cause is a mismatched working directory. Sessions are stored under `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, where `<encoded-cwd>` is the absolute working directory with every non-alphanumeric character replaced by `-` (so `/Users/me/proj` becomes `-Users-me-proj`). If your resume call runs from a different directory, the SDK looks in the wrong place. The session file also needs to exist on the current machine.

### Continuing the most recent conversation

Use `:continue` to automatically resume the last conversation in the current directory without tracking session IDs:

```elixir
{:ok, session} = ClaudeCode.start_link(continue: true)

session
|> ClaudeCode.stream("What were we talking about?")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

## Fork to explore alternatives

Forking creates a new session that starts with a copy of the original's history but diverges from that point. The fork gets its own session ID; the original's ID and history stay unchanged. You end up with two independent sessions you can resume separately.

> **Note:** Forking branches the conversation history, not the filesystem. If a forked agent edits files, those changes are real and visible to any session working in the same directory. To branch and revert file changes, use [File Checkpointing](file-checkpointing.md).

This example forks a session to explore an alternative approach while keeping the original intact:

```elixir
# First, capture the session ID
{:ok, session} = ClaudeCode.start_link(model: "claude-opus-4-6")
session |> ClaudeCode.stream("Help me design a REST API") |> Stream.run()
session_id = ClaudeCode.Session.session_id(session)
ClaudeCode.stop(session)

# Fork: branch from session_id into a new session
{:ok, forked} = ClaudeCode.start_link(
  resume: session_id,
  fork_session: true
)

forked
|> ClaudeCode.stream("Instead of REST, implement OAuth2 for the auth module")
|> ClaudeCode.Stream.final_text()

# The fork has a new session ID, distinct from session_id
forked_id = ClaudeCode.Session.session_id(forked)
ClaudeCode.stop(forked)

# Original session is untouched; resuming it continues the original thread
{:ok, continued} = ClaudeCode.start_link(resume: session_id)

continued
|> ClaudeCode.stream("Continue with the REST API design")
|> ClaudeCode.Stream.final_text()

ClaudeCode.stop(continued)
```

## Resume across hosts

Session files are local to the machine that created them. To resume a session on a different host (CI workers, ephemeral containers, serverless), you have two options:

- **Move the session file.** Persist `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` from the first run and restore it to the same path on the new host before calling resume. The working directory must match.
- **Don't rely on session resume.** Capture the results you need (analysis output, decisions, file diffs) as application state and pass them into a fresh session's prompt. This is often more robust than shipping transcript files around.

The SDK provides `ClaudeCode.Session.conversation/2` for reading session messages from disk. Use it to build custom session pickers, cleanup logic, or transcript viewers.

## Clearing Context

Reset conversation history without stopping the session:

```elixir
ClaudeCode.Session.clear(session)

# Next query starts fresh
session
|> ClaudeCode.stream("Hello!")
|> ClaudeCode.Stream.final_text()
```

## Reading Conversation History

Access past conversations stored in `~/.claude/projects/`:

```elixir
# By session ID
{:ok, messages} = ClaudeCode.Session.conversation("abc123-def456")

Enum.each(messages, fn
  %ClaudeCode.Message.UserMessage{message: %{content: content}} ->
    Logger.info("User: #{inspect(content)}")
  %ClaudeCode.Message.AssistantMessage{message: %{content: blocks}} ->
    text = Enum.map_join(blocks, "", fn
      %ClaudeCode.Content.TextBlock{text: t} -> t
      _ -> ""
    end)
    Logger.info("Assistant: #{text}")
  _ ->
    :ok
end)

# From a running session
{:ok, messages} = ClaudeCode.Session.conversation(session)
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
{:ok, _} = ClaudeCode.Session.set_model(session, "claude-sonnet-4-5-20250929")

# Change permission mode
{:ok, _} = ClaudeCode.Session.set_permission_mode(session, :bypass_permissions)

# Query MCP server status
{:ok, %{"servers" => servers}} = ClaudeCode.Session.mcp_status(session)

# Rewind files to a checkpoint (requires enable_file_checkpointing: true)
{:ok, _} = ClaudeCode.Session.rewind_files(session, "user-msg-uuid-123")

# Get server info from the initialize handshake
{:ok, info} = ClaudeCode.Session.server_info(session)
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
| `Session.clear/1`    | Resets session ID, next query starts fresh                    |
| `stop/1`             | Terminates GenServer and CLI subprocess                       |
| Process crash        | Supervisor restarts if supervised                             |

## Related Resources

- [Streaming Output](streaming-output.md) - Real-time character-level streaming
- [Hosting](hosting.md) - Production deployment with OTP
- [File Checkpointing](file-checkpointing.md) - Track and revert file changes
- [Stop Reasons](stop-reasons.md) - Understanding turns, messages, and result handling
