# File Checkpointing

Track file changes during agent sessions and restore files to any previous state.

## Overview

File checkpointing tracks file modifications made through the Write, Edit, and NotebookEdit tools during an agent session, allowing you to rewind files to any previous state.

With checkpointing, you can:

- **Undo unwanted changes** by restoring files to a known good state
- **Explore alternatives** by restoring to a checkpoint and trying a different approach
- **Recover from errors** when the agent makes incorrect modifications

> Only changes made through the Write, Edit, and NotebookEdit tools are tracked. Changes made through Bash commands (like `echo > file.txt` or `sed -i`) are not captured by the checkpoint system.

## How checkpointing works

When you enable file checkpointing, the CLI creates backups of files before modifying them. User messages in the response stream include a UUID that you can use as a restore point.

The checkpoint system tracks:

- Files created during the session
- Files modified during the session
- The original content of modified files

When you rewind to a checkpoint, created files are deleted and modified files are restored to their content at that point.

> File rewinding restores files on disk to a previous state. It does not rewind the conversation itself. The conversation history and context remain intact after calling `ClaudeCode.rewind_files/2`.

## Enabling checkpointing

```elixir
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  permission_mode: :accept_edits
)
```

The `enable_file_checkpointing: true` option sets the `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` environment variable for the CLI subprocess automatically.

## Capturing checkpoint UUIDs

Each user message in the response stream has a `uuid` field that serves as a checkpoint. Capture the first user message UUID to get a restore point for the session's initial state.

```elixir
checkpoint_id = nil
session_id = nil

session
|> ClaudeCode.stream("Refactor the authentication module")
|> Enum.reduce({nil, nil}, fn message, {cp, sid} ->
  cp = case message do
    %ClaudeCode.Message.UserMessage{uuid: uuid} when not is_nil(uuid) and is_nil(cp) -> uuid
    _ -> cp
  end

  sid = case message do
    %ClaudeCode.Message.ResultMessage{session_id: id} when not is_nil(id) -> id
    _ -> sid
  end

  {cp, sid}
end)
```

## Rewinding files

Use `ClaudeCode.rewind_files/2` with the checkpoint UUID to restore files:

```elixir
{:ok, _} = ClaudeCode.rewind_files(session, checkpoint_id)
```

This sends a control protocol request to the CLI to restore all tracked files to their state at the given checkpoint.

## Complete example

```elixir
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  permission_mode: :accept_edits
)

# Run a query and capture the first user message UUID as a checkpoint
{checkpoint_id, _session_id} =
  session
  |> ClaudeCode.stream("Add doc comments to lib/my_app/utils.ex")
  |> Enum.reduce({nil, nil}, fn message, {cp, sid} ->
    cp = case message do
      %ClaudeCode.Message.UserMessage{uuid: uuid} when not is_nil(uuid) and is_nil(cp) -> uuid
      _ -> cp
    end
    sid = case message do
      %ClaudeCode.Message.ResultMessage{session_id: id} when not is_nil(id) -> id
      _ -> sid
    end
    {cp, sid}
  end)

IO.puts("Changes made. Checkpoint: #{checkpoint_id}")

# Review the changes, then rewind if needed
{:ok, _} = ClaudeCode.rewind_files(session, checkpoint_id)
IO.puts("Files restored to original state.")
```

## Common patterns

### Checkpoint before risky operations

Keep the most recent checkpoint UUID, updating it before each agent turn. If something goes wrong, rewind immediately:

```elixir
session
|> ClaudeCode.stream("Refactor the authentication module")
|> Enum.reduce_while(nil, fn message, safe_checkpoint ->
  # Update checkpoint on each user message
  safe_checkpoint = case message do
    %ClaudeCode.Message.UserMessage{uuid: uuid} when not is_nil(uuid) -> uuid
    _ -> safe_checkpoint
  end

  # Check your own revert condition
  if should_revert?(message) and safe_checkpoint do
    ClaudeCode.rewind_files(session, safe_checkpoint)
    {:halt, safe_checkpoint}
  else
    {:cont, safe_checkpoint}
  end
end)
```

### Multiple restore points

Store all checkpoint UUIDs to rewind to any specific point:

```elixir
defmodule Checkpoint do
  defstruct [:id, :description, :timestamp]
end

checkpoints =
  session
  |> ClaudeCode.stream("Refactor the authentication module")
  |> Enum.reduce([], fn message, acc ->
    case message do
      %ClaudeCode.Message.UserMessage{uuid: uuid} when not is_nil(uuid) ->
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

| Limitation | Description |
|------------|-------------|
| Write/Edit/NotebookEdit only | Changes made through Bash commands are not tracked |
| Same session | Checkpoints are tied to the session that created them |
| File content only | Creating, moving, or deleting directories is not undone by rewinding |
| Local files | Remote or network files are not tracked |

## Next Steps

- [Secure Deployment](secure-deployment.md) - Sandboxing and production security
- [Sessions](sessions.md) - Session management and resuming
