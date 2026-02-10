# Modifying System Prompts

Customize Claude's behavior by modifying system prompts using custom prompts, appended instructions, and CLAUDE.md project files.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/modifying-system-prompts). Examples are adapted for Elixir.

---

System prompts define Claude's behavior, capabilities, and response style. The Elixir SDK provides several ways to customize system prompts: using CLAUDE.md files for project-level instructions, appending to the default prompt, using a fully custom prompt, or passing settings directly.

## Understanding system prompts

A system prompt is the initial instruction set that shapes how Claude behaves throughout a conversation.

> **Default behavior:** The Agent SDK uses a **minimal system prompt** by default. It contains only essential tool instructions but omits Claude Code's coding guidelines, response style, and project context. To customize behavior, use `:system_prompt` to replace the default entirely, or `:append_system_prompt` to add instructions while keeping the defaults.

Claude Code's default system prompt includes:

- Tool usage instructions and available tools
- Code style and formatting guidelines
- Response tone and verbosity settings
- Security and safety instructions
- Context about the current working directory and environment

## Methods of modification

### Method 1: CLAUDE.md files (project-level instructions)

CLAUDE.md files provide project-specific context and instructions that are automatically read by the SDK when configured with `:setting_sources`. They serve as persistent "memory" for your project.

#### How CLAUDE.md works with the SDK

**Location and discovery:**

- **Project-level:** `CLAUDE.md` or `.claude/CLAUDE.md` in your working directory
- **User-level:** `~/.claude/CLAUDE.md` for global instructions across all projects

The SDK only reads CLAUDE.md files when you explicitly configure `:setting_sources`:

- Include `"project"` to load project-level CLAUDE.md
- Include `"user"` to load user-level CLAUDE.md (`~/.claude/CLAUDE.md`)

**Content format:**
CLAUDE.md files use plain markdown and can contain:

- Coding guidelines and standards
- Project-specific context
- Common commands or workflows
- API conventions
- Testing requirements

#### Example CLAUDE.md

```markdown
# Project Guidelines

## Code Style
- Use Elixir 1.18+ features
- Prefer pattern matching over conditionals
- Always include @moduledoc and @doc attributes

## Testing
- Run `mix test` before committing
- Maintain >80% code coverage
- Use ExUnit with Mox for mocking

## Commands
- Quality checks: `mix quality`
- Dev server: `iex -S mix phx.server`
- Type check: `mix dialyzer`
```

#### Using CLAUDE.md with the SDK

```elixir
# You must specify setting_sources to load CLAUDE.md
{:ok, result} = ClaudeCode.query("Add a new GenServer module for user sessions",
  setting_sources: ["project"]
)
```

#### When to use CLAUDE.md

**Best for:**

- **Team-shared context** -- Guidelines everyone should follow
- **Project conventions** -- Coding standards, file structure, naming patterns
- **Common commands** -- Build, test, deploy commands specific to your project
- **Long-term memory** -- Context that should persist across all sessions
- **Version-controlled instructions** -- Commit to git so the team stays in sync

**Key characteristics:**

- Persistent across all sessions in a project
- Shared with team via git
- Automatic discovery (no code changes needed beyond setting sources)
- Requires loading settings via `:setting_sources`

### Method 2: Appending to the system prompt

Use `:append_system_prompt` to add your custom instructions while preserving all built-in functionality. This is the recommended approach for most use cases.

```elixir
{:ok, result} = ClaudeCode.query("Help me process this large CSV file",
  append_system_prompt: "Focus on performance optimization. Prefer Stream over Enum for large datasets."
)
```

This keeps Claude's tool-usage instructions, safety guidelines, and environment context intact while adding your custom behavior.

### Method 3: Custom system prompts

Use `:system_prompt` to replace the default system prompt entirely with your own instructions:

```elixir
{:ok, result} = ClaudeCode.query("Create a data processing pipeline",
  system_prompt: """
  You are an Elixir coding specialist.
  Follow these guidelines:
  - Write clean, well-documented code
  - Use typespecs for all public functions
  - Include comprehensive @moduledoc and @doc attributes
  - Prefer functional programming patterns
  - Always explain your code choices
  """
)
```

> **Warning:** Overriding the system prompt replaces Claude Code's default instructions, which include tool usage guidance, safety instructions, and environment context. Only use this when you need complete control over Claude's behavior.

### Method 4: Settings configuration

Pass settings directly as a map or file path using the `:settings` option:

```elixir
# As a map (auto-encoded to JSON for the CLI)
{:ok, session} = ClaudeCode.start_link(
  settings: %{
    "preferredLanguage" => "elixir",
    "codeStyle" => "functional"
  }
)

# Or as a path to a JSON file
{:ok, session} = ClaudeCode.start_link(
  settings: "/path/to/settings.json"
)
```

## Comparison of approaches

| Feature | CLAUDE.md | `:append_system_prompt` | Custom `:system_prompt` | `:settings` |
|:--------|:----------|:------------------------|:------------------------|:------------|
| **Persistence** | Per-project file | Session only | Session only | Session only |
| **Reusability** | Per-project | Code duplication | Code duplication | File or code |
| **Default tools** | Preserved | Preserved | Lost (unless included) | Preserved |
| **Built-in safety** | Maintained | Maintained | Must be added | Maintained |
| **Environment context** | Automatic | Automatic | Must be provided | Automatic |
| **Customization level** | Additions only | Additions only | Complete control | Key-value config |
| **Version control** | With project | With code | With code | File or code |
| **Scope** | Project-specific | Code session | Code session | Code session |

## Per-query overrides

Both `:system_prompt` and `:append_system_prompt` can be overridden at the query level. Query-level options take precedence over session defaults for that single query only:

```elixir
{:ok, session} = ClaudeCode.start_link(
  append_system_prompt: "You are a general coding assistant."
)

# This query uses a different system prompt override
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

## Use cases and best practices

### When to use CLAUDE.md

- Project-specific coding standards and conventions
- Documenting project structure and architecture
- Listing common commands (build, test, deploy)
- Team-shared context that should be version controlled
- Instructions that apply to all SDK usage in a project

### When to use `:append_system_prompt`

- Adding specific coding standards or preferences
- Customizing output formatting
- Adding domain-specific knowledge
- Modifying response verbosity
- Enhancing Claude Code's default behavior without losing tool instructions

### When to use custom `:system_prompt`

- Complete control over Claude's behavior
- Specialized single-session tasks
- Testing new prompt strategies
- Situations where default tools are not needed
- Building specialized agents with unique behavior

## Combining approaches

You can combine these methods for maximum flexibility:

```elixir
{:ok, result} = ClaudeCode.query("Review this authentication module",
  # Keep default instructions, add custom ones
  append_system_prompt: "You write idiomatic Elixir. Use pattern matching over conditionals.",
  # Load project CLAUDE.md
  setting_sources: ["project"],
  # Additional settings
  settings: %{"preferredTestFramework" => "ExUnit"}
)
```

### Loading multiple setting sources

The `:setting_sources` option accepts a list of sources to load:

```elixir
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["user", "project", "local"]
)
```

Available sources:

| Source | Description |
|:-------|:------------|
| `"user"` | User-level settings (`~/.claude/CLAUDE.md`) |
| `"project"` | Project-level settings (CLAUDE.md in project root) |
| `"local"` | Local settings (`.claude/settings.local.json`) |

## Next steps

- [Permissions](permissions.md) -- Control tool access
- [Subagents](subagents.md) -- Custom agent definitions with specialized prompts
- [Sessions](sessions.md) -- Session management and multi-turn conversations
