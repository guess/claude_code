# Skills

Skills are project-level capabilities that Claude can use during a conversation. They are defined in project configuration files and loaded via setting sources.

## Loading Skills

Skills are loaded from project settings:

```elixir
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["project"]
)
```

## Detecting Available Skills

The `SystemMessage` lists available skills:

```elixir
session
|> ClaudeCode.stream("Hello")
|> Enum.each(fn
  %ClaudeCode.Message.SystemMessage{skills: skills} ->
    IO.puts("Available skills: #{inspect(skills)}")
  _ -> :ok
end)
```

## Next Steps

- [Slash Commands](slash-commands.md) - Predefined prompt commands
- [Plugins](plugins.md) - Plugin configuration
- [Modifying System Prompts](modifying-system-prompts.md) - Customize Claude's behavior
