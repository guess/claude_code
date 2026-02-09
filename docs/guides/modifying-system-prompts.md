# Modifying System Prompts

Customize Claude's behavior with system prompts.

## Override System Prompt

Replace the default system prompt entirely:

```elixir
{:ok, session} = ClaudeCode.start_link(
  system_prompt: "You are an Elixir expert. Always respond with code examples."
)
```

> **Note**: Overriding the system prompt replaces Claude Code's default instructions, which include tool usage guidance. Use `append_system_prompt` to add instructions while keeping defaults.

## Append to System Prompt

Add instructions while preserving Claude Code's default behavior:

```elixir
{:ok, session} = ClaudeCode.start_link(
  append_system_prompt: "Focus on performance optimization. Prefer Stream over Enum for large datasets."
)
```

This is the recommended approach for most use cases, as it keeps Claude's tool-usage instructions intact.

## Per-Query Overrides

Override the system prompt for individual queries:

```elixir
{:ok, session} = ClaudeCode.start_link(
  system_prompt: "You are a general assistant."
)

# This query uses a different system prompt
session
|> ClaudeCode.stream("Review this module",
     system_prompt: "You are a security auditor. Focus on OWASP vulnerabilities.")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Next query goes back to the session default
session
|> ClaudeCode.stream("Help me write tests")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

## CLAUDE.md via Setting Sources

Load project-level instructions from CLAUDE.md files:

```elixir
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["project"]
)
```

This tells the CLI to load CLAUDE.md files from the project directory, giving Claude context about your codebase conventions.

Available sources:
- `"user"` - User-level settings (`~/.claude/`)
- `"project"` - Project-level settings (CLAUDE.md in project root)
- `"local"` - Local settings (`.claude/settings.local.json`)

```elixir
# Load all setting sources
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["user", "project", "local"]
)
```

## Settings as a Map

Pass settings directly as a map:

```elixir
{:ok, session} = ClaudeCode.start_link(
  settings: %{
    "preferredLanguage" => "elixir",
    "codeStyle" => "functional"
  }
)
```

Or as a path to a JSON file:

```elixir
{:ok, session} = ClaudeCode.start_link(
  settings: "/path/to/settings.json"
)
```

## Combining Approaches

```elixir
{:ok, session} = ClaudeCode.start_link(
  # Keep default instructions, add custom ones
  append_system_prompt: "You write idiomatic Elixir. Use pattern matching over conditionals.",
  # Load project CLAUDE.md
  setting_sources: ["project"],
  # Additional settings
  settings: %{"preferredTestFramework" => "ExUnit"}
)
```

## Next Steps

- [Permissions](permissions.md) - Control tool access
- [Subagents](subagents.md) - Custom agent definitions with specialized prompts
