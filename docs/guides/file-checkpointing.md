# Rewind File Changes with Checkpointing

Track file changes during agent sessions and restore files to any previous state.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/file-checkpointing). Examples are adapted for Elixir.

File checkpointing tracks file modifications made through the Write, Edit, and NotebookEdit tools during an agent session, allowing you to rewind files to any previous state.

With checkpointing, you can:

- **Undo unwanted changes** by restoring files to a known good state
- **Explore alternatives** by restoring to a checkpoint and trying a different approach
- **Recover from errors** when the agent makes incorrect modifications

> Only changes made through the Write, Edit, and NotebookEdit tools are tracked. Changes made through Bash commands (like `echo > file.txt` or `sed -i`) are not captured by the checkpoint system.

## How checkpointing works

When you enable file checkpointing, the SDK creates backups of files before modifying them through the Write, Edit, or NotebookEdit tools. User messages in the response stream include a checkpoint UUID that you can use as a restore point.

Checkpointing works with these built-in tools that the agent uses to modify files:

| Tool         | Description                                                        |
| ------------ | ------------------------------------------------------------------ |
| Write        | Creates a new file or overwrites an existing file with new content |
| Edit         | Makes targeted edits to specific parts of an existing file         |
| NotebookEdit | Modifies cells in Jupyter notebooks (`.ipynb` files)               |

> File rewinding restores files on disk to a previous state. It does not rewind the conversation itself. The conversation history and context remain intact after calling `ClaudeCode.rewind_files/2`.

The checkpoint system tracks:

- Files created during the session
- Files modified during the session
- The original content of modified files

When you rewind to a checkpoint, created files are deleted and modified files are restored to their content at that point.

## Implement checkpointing

To use file checkpointing, enable it in your session options, capture checkpoint UUIDs from the response stream, then call `ClaudeCode.rewind_files/2` when you need to restore.

The following example shows the complete flow: enable checkpointing, capture the checkpoint UUID from the response stream, then rewind files. Each step is explained in detail below.

```elixir
alias ClaudeCode.Message.UserMessage

# Step 1: Enable checkpointing
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  permission_mode: :accept_edits
)

# Step 2: Run a query and capture the first user message UUID as a checkpoint
checkpoint_id =
  session
  |> ClaudeCode.stream("Refactor the authentication module")
  |> Enum.reduce(nil, fn
    %UserMessage{uuid: uuid}, nil when not is_nil(uuid) -> uuid
    _, cp -> cp
  end)

# Step 3: Rewind files to the checkpoint
{:ok, _} = ClaudeCode.rewind_files(session, checkpoint_id)
```

### Step 1: Enable checkpointing

Configure your session with `enable_file_checkpointing: true`. This automatically sets the `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` environment variable for the CLI subprocess.

| Option                            | Description                              |
| --------------------------------- | ---------------------------------------- |
| `enable_file_checkpointing: true` | Tracks file changes for rewinding        |
| `permission_mode: :accept_edits`  | Auto-accept file edits without prompting |

```elixir
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  permission_mode: :accept_edits
)
```

> The Elixir SDK uses `--input-format stream-json` for bidirectional streaming, so user messages with checkpoint UUIDs are automatically included in the response stream. No additional flags are needed (unlike the Python/TypeScript SDKs which require `extra_args: {"replay-user-messages": None}`).

### Step 2: Capture checkpoint UUID

Each user message in the response stream has a `uuid` field that serves as a checkpoint.

For most use cases, capture the first user message UUID; rewinding to it restores all files to their original state. To store multiple checkpoints and rewind to intermediate states, see [Multiple restore points](#multiple-restore-points).

```elixir
alias ClaudeCode.Message.UserMessage

checkpoint_id =
  session
  |> ClaudeCode.stream("Refactor the authentication module")
  |> Enum.reduce(nil, fn
    %UserMessage{uuid: uuid}, nil when not is_nil(uuid) -> uuid
    _, cp -> cp
  end)
```

> If you also need the session ID (for example, to resume from the CLI later), use `ClaudeCode.Stream.final_result/1` instead — it returns the full `ClaudeCode.Message.ResultMessage` which includes `session_id`. However, for rewinding you don't need it — the Elixir SDK keeps the session alive as a GenServer, so you can call `ClaudeCode.rewind_files/2` directly.

### Step 3: Rewind files

Call `ClaudeCode.rewind_files/2` with the session and checkpoint UUID to restore files:

```elixir
{:ok, _} = ClaudeCode.rewind_files(session, checkpoint_id)
```

Since the Elixir SDK maintains a persistent GenServer session, you can rewind at any time while the session is alive — no need to resume with an empty prompt as in the Python/TypeScript SDKs.

You can also rewind from the CLI if you have the session ID and checkpoint UUID:

```bash
claude --resume <session-id> --rewind-files <checkpoint-uuid>
```

To get the session ID programmatically, use `ClaudeCode.Stream.final_result/1`:

```elixir
result =
  session
  |> ClaudeCode.stream("Refactor the authentication module")
  |> ClaudeCode.Stream.final_result()

IO.puts("Session ID: #{result.session_id}")
```

## Common patterns

These patterns show different ways to capture and use checkpoint UUIDs depending on your use case.

### Checkpoint before risky operations

This pattern keeps only the most recent checkpoint UUID, updating it before each agent turn. If something goes wrong during processing, you can immediately rewind to the last safe state and break out of the stream.

```elixir
alias ClaudeCode.Message.UserMessage

session
|> ClaudeCode.stream("Refactor the authentication module")
|> Enum.reduce_while(nil, fn message, safe_checkpoint ->
  # Update checkpoint on each user message (keeps the latest)
  safe_checkpoint = case message do
    %UserMessage{uuid: uuid} when not is_nil(uuid) -> uuid
    _ -> safe_checkpoint
  end

  # Decide when to revert based on your own logic
  # For example: error detection, validation failure, or user input
  if should_revert?(message) and safe_checkpoint do
    ClaudeCode.rewind_files(session, safe_checkpoint)
    # Exit the stream after rewinding, files are restored
    {:halt, safe_checkpoint}
  else
    {:cont, safe_checkpoint}
  end
end)
```

### Multiple restore points

If Claude makes changes across multiple turns, you might want to rewind to a specific point rather than all the way back. For example, if Claude refactors a file in turn one and adds tests in turn two, you might want to keep the refactor but undo the tests.

This pattern stores all checkpoint UUIDs in a list with metadata. After the session completes, you can rewind to any previous checkpoint:

```elixir
alias ClaudeCode.Message.UserMessage

defmodule Checkpoint do
  defstruct [:id, :description, :timestamp]
end

checkpoints =
  session
  |> ClaudeCode.stream("Refactor the authentication module")
  |> Enum.reduce([], fn message, acc ->
    case message do
      %UserMessage{uuid: uuid} when not is_nil(uuid) ->
        checkpoint = %Checkpoint{
          id: uuid,
          description: "After turn #{length(acc) + 1}",
          timestamp: DateTime.utc_now()
        }
        [checkpoint | acc]

      _ -> acc
    end
  end)
  |> Enum.reverse()

# Rewind to any checkpoint
target = List.first(checkpoints)
{:ok, _} = ClaudeCode.rewind_files(session, target.id)
```

## Combining with sandbox mode

For maximum safety, combine file checkpointing with sandboxing:

```elixir
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  permission_mode: :accept_edits,
  sandbox: %{
    "environment" => "docker",
    "container" => "my-sandbox"
  }
)
```

## Limitations

File checkpointing has the following limitations:

| Limitation                         | Description                                                          |
| ---------------------------------- | -------------------------------------------------------------------- |
| Write/Edit/NotebookEdit tools only | Changes made through Bash commands are not tracked                   |
| Same session                       | Checkpoints are tied to the session that created them                |
| File content only                  | Creating, moving, or deleting directories is not undone by rewinding |
| Local files                        | Remote or network files are not tracked                              |

## Troubleshooting

### User messages don't have UUIDs

If `uuid` is `nil` on user messages, ensure `enable_file_checkpointing: true` is set in your session options. The Elixir SDK automatically handles the `--input-format stream-json` flag which includes user messages in the response stream.

### "No file checkpoint found for message" error

This error occurs when the checkpoint data doesn't exist for the specified user message UUID.

**Common causes:**

- The `enable_file_checkpointing: true` option wasn't set when starting the session
- The session wasn't properly completed before attempting to rewind

**Solution:** Ensure `enable_file_checkpointing: true` is passed to `ClaudeCode.start_link/1`, then capture the user message UUID from the response stream and call `ClaudeCode.rewind_files/2` while the session is still alive.

## Next steps

- [Sessions](sessions.md) — Session management and resuming, which covers session IDs and multi-turn conversations
- [Secure Deployment](secure-deployment.md) — Sandboxing and production security
