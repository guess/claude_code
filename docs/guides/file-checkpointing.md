# File Checkpointing

Track file changes during agent sessions and restore files to any previous state. Want to try it out? Jump to the [interactive example](#try-it-out).

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/file-checkpointing). Examples are adapted for Elixir.

File checkpointing tracks file modifications made through the Write, Edit, and NotebookEdit tools during an agent session, allowing you to rewind files to any previous state.

With checkpointing, you can:

- **Undo unwanted changes** by restoring files to a known good state
- **Explore alternatives** by restoring to a checkpoint and trying a different approach
- **Recover from errors** when the agent makes incorrect modifications

> Only changes made through the Write, Edit, and NotebookEdit tools are tracked. Changes made through Bash commands (like `echo > file.txt` or `sed -i`) are not captured by the checkpoint system.

## How checkpointing works

When you enable file checkpointing, the SDK creates backups of files before modifying them through the Write, Edit, or NotebookEdit tools. User messages in the response stream include a checkpoint UUID that you can use as a restore point.

Checkpoint works with these built-in tools that the agent uses to modify files:

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

To use file checkpointing, enable it in your options, capture checkpoint UUIDs from the response stream, then call `ClaudeCode.rewind_files/2` when you need to restore.

The following example shows the complete flow: enable checkpointing, capture the checkpoint UUID and session ID from the response stream, then rewind files. Each step is explained in detail below.

```elixir
alias ClaudeCode.Message.UserMessage

# Steps 1-2: Enable checkpointing (env var is set automatically)
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  permission_mode: :accept_edits
)

# Step 3: Run a query and capture the first user message UUID as a checkpoint
checkpoint_id =
  session
  |> ClaudeCode.stream("Refactor the authentication module")
  |> Enum.reduce(nil, fn
    %UserMessage{uuid: uuid}, nil when not is_nil(uuid) -> uuid
    _, cp -> cp
  end)

# Step 4: Rewind files to the checkpoint
{:ok, _} = ClaudeCode.rewind_files(session, checkpoint_id)
```

### Step 1: Set the environment variable

File checkpointing requires the `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` environment variable. The Elixir SDK sets this automatically when you pass `enable_file_checkpointing: true` to `ClaudeCode.start_link/1` -- no manual env var setup is needed.

You can also set it via the command line before running your script:

```bash
export CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING=1
```

### Step 2: Enable checkpointing

Configure your session with `enable_file_checkpointing: true`:

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

### Step 3: Capture checkpoint UUID and session ID

With `enable_file_checkpointing: true` set, each user message in the response stream has a `uuid` field that serves as a checkpoint.

For most use cases, capture the first user message UUID; rewinding to it restores all files to their original state. To store multiple checkpoints and rewind to intermediate states, see [Multiple restore points](#multiple-restore-points).

Capturing the session ID is optional; you only need it if you want to rewind later from the CLI. Since the Elixir SDK maintains a persistent GenServer session, you can call `ClaudeCode.rewind_files/2` directly at any time while the session is alive.

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

> If you also need the session ID (for example, to resume from the CLI later), use `ClaudeCode.Stream.final_result/1` instead -- it returns the full `ClaudeCode.Message.ResultMessage` which includes `session_id`.

### Step 4: Rewind files

Call `ClaudeCode.rewind_files/2` with the session and checkpoint UUID to restore files:

```elixir
{:ok, _} = ClaudeCode.rewind_files(session, checkpoint_id)
```

Since the Elixir SDK maintains a persistent GenServer session, you can rewind at any time while the session is alive -- no need to resume with an empty prompt as in the Python/TypeScript SDKs.

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

session_id = result.session_id
```

## Common patterns

These patterns show different ways to capture and use checkpoint UUIDs depending on your use case.

### Checkpoint before risky operations

This pattern keeps only the most recent checkpoint UUID, updating it before each agent turn. If something goes wrong during processing, you can immediately rewind to the last safe state and break out of the loop.

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

## Try it out

This complete example creates a small utility module, has the agent add documentation comments, shows you the changes, then asks if you want to rewind.

Before you begin, make sure you have the ClaudeCode Elixir SDK installed as a dependency in your Mix project.

### 1. Create a test file

Create a new file called `utils.ex`:

```elixir
# utils.ex
defmodule Utils do
  def add(a, b), do: a + b

  def subtract(a, b), do: a - b

  def multiply(a, b), do: a * b

  def divide(_a, 0), do: {:error, "Cannot divide by zero"}
  def divide(a, b), do: {:ok, a / b}
end
```

### 2. Run the interactive example

Create a new file called `try_checkpointing.exs` in the same directory as your utility file, and paste the following code. This script asks Claude to add doc comments to your utility file, then gives you the option to rewind and restore the original.

```elixir
# try_checkpointing.exs
alias ClaudeCode.Message.UserMessage

# Configure the session with checkpointing enabled
# - enable_file_checkpointing: Track file changes for rewinding
# - permission_mode: Auto-accept file edits without prompting
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  permission_mode: :accept_edits
)

IO.puts("Running agent to add doc comments to utils.ex...\n")

# Run the agent and capture the first user message UUID as a checkpoint
checkpoint_id =
  session
  |> ClaudeCode.stream("Add @doc and @spec annotations to utils.ex")
  |> Enum.reduce(nil, fn
    %UserMessage{uuid: uuid}, nil when not is_nil(uuid) -> uuid
    _, cp -> cp
  end)

IO.puts("Done! Open utils.ex to see the added doc comments.\n")

# Ask the user if they want to rewind the changes
if checkpoint_id do
  answer = IO.gets("Rewind to remove the doc comments? (y/n): ") |> String.trim()

  if answer == "y" do
    {:ok, _} = ClaudeCode.rewind_files(session, checkpoint_id)
    IO.puts("\nFile restored! Open utils.ex to verify the doc comments are gone.")
  else
    IO.puts("\nKept the modified file.")
  end
end

ClaudeCode.stop(session)
```

This example demonstrates the complete checkpointing workflow:

1. **Enable checkpointing**: configure the session with `enable_file_checkpointing: true` and `permission_mode: :accept_edits` to auto-approve file edits
2. **Capture checkpoint data**: as the agent runs, store the first user message UUID (your restore point) and the session ID
3. **Prompt for rewind**: after the agent finishes, check your utility file to see the doc comments, then decide if you want to undo the changes
4. **Rewind**: if yes, call `ClaudeCode.rewind_files/2` to restore the original file

### 3. Run the example

Run the script from the same directory as your utility file:

```bash
elixir -S mix run try_checkpointing.exs
```

> Open your utility file (`utils.ex`) in your editor before running the script. You'll see the file update in real-time as the agent adds doc comments, then revert back to the original when you choose to rewind.

## Limitations

File checkpointing has the following limitations:

| Limitation                         | Description                                                          |
| ---------------------------------- | -------------------------------------------------------------------- |
| Write/Edit/NotebookEdit tools only | Changes made through Bash commands are not tracked                   |
| Same session                       | Checkpoints are tied to the session that created them                |
| File content only                  | Creating, moving, or deleting directories is not undone by rewinding |
| Local files                        | Remote or network files are not tracked                              |

## Troubleshooting

### Checkpointing options not recognized

If `enable_file_checkpointing` isn't available or `ClaudeCode.rewind_files/2` isn't defined, you may be on an older SDK version.

**Solution:** Update to the latest SDK version in your `mix.exs`:

```elixir
{:claude_code, "~> 0.23"}
```

Then run `mix deps.get`.

### User messages don't have UUIDs

If `uuid` is `nil` on user messages, ensure `enable_file_checkpointing: true` is set in your session options. The Elixir SDK automatically handles the `--input-format stream-json` flag which includes user messages in the response stream.

### "No file checkpoint found for message" error

This error occurs when the checkpoint data doesn't exist for the specified user message UUID.

**Common causes:**

- The `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING` environment variable isn't set (the Elixir SDK sets this automatically when `enable_file_checkpointing: true` is passed)
- The `enable_file_checkpointing: true` option wasn't set when starting the session
- The session wasn't properly completed before attempting to rewind

**Solution:** Ensure `enable_file_checkpointing: true` is passed to `ClaudeCode.start_link/1`, then capture the user message UUID from the response stream and call `ClaudeCode.rewind_files/2` while the session is still alive.

## Next steps

- [Sessions](sessions.md) -- Learn how to resume sessions, which is required for rewinding from the CLI after the stream completes. Covers session IDs, resuming conversations, and session forking.
- [Permissions](permissions.md) -- Configure which tools Claude can use and how file modifications are approved. Useful if you want more control over when edits happen.
