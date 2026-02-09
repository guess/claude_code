# File Checkpointing

Track file changes made during a session for auditing or rollback purposes.

## Enabling File Checkpointing

```elixir
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true
)
```

When enabled, the CLI tracks all file modifications made by Claude during the session. This is set via an environment variable (`CLAUDE_CODE_ENABLE_FILE_CHECKPOINTING=1`) rather than a CLI flag.

## Combining with Sandbox Mode

For maximum safety, combine file checkpointing with sandboxing:

```elixir
{:ok, session} = ClaudeCode.start_link(
  enable_file_checkpointing: true,
  sandbox: %{
    "environment" => "docker",
    "container" => "my-sandbox"
  }
)
```

The `sandbox` option is merged into `--settings` as `{"sandbox": {...}}` and controls how the CLI isolates bash command execution.

## Use Cases

- **Auditing**: Track exactly which files Claude modified during a session
- **Safety net**: Know what changed before committing to version control
- **Experimentation**: Let Claude make changes with the ability to review them

## SDK Limitation: Rewind

The Agent SDK (Python/TypeScript) provides a `rewindFiles()` method to programmatically revert file changes to a checkpoint. This is **not yet available** in the Elixir SDK.

Current alternatives:
- Use `git diff` / `git checkout` to review and revert changes
- Run sessions in a Docker container or temporary directory
- Use the `sandbox:` option for bash command isolation

## Next Steps

- [Secure Deployment](secure-deployment.md) - Sandboxing and production security
- [Sessions](sessions.md) - Session management
