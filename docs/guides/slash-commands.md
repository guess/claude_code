# Slash Commands

Slash commands are predefined prompts that can be invoked by Claude during a conversation. They are typically defined in a project's CLAUDE.md or settings files.

## Loading Slash Commands

Slash commands are loaded from project settings. Use `setting_sources` to enable them:

```elixir
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["project"]
)
```

This loads CLAUDE.md and any configured slash commands from your project directory.

## Disabling Slash Commands

```elixir
{:ok, session} = ClaudeCode.start_link(
  disable_slash_commands: true
)
```

## Detecting Slash Commands

The `SystemMessage` emitted at the start of a query lists available slash commands:

```elixir
session
|> ClaudeCode.stream("Hello")
|> Enum.each(fn
  %ClaudeCode.Message.SystemMessage{slash_commands: commands} ->
    IO.puts("Available commands: #{inspect(commands)}")
  _ -> :ok
end)
```

## Next Steps

- [Skills](skills.md) - Project-level skill definitions
- [Modifying System Prompts](modifying-system-prompts.md) - Customize Claude's behavior
