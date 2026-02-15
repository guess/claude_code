# Modifying System Prompts

Learn how to customize Claude's behavior by modifying system prompts using output styles, appended instructions, and custom system prompts.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/modifying-system-prompts). Examples are adapted for Elixir.

---

System prompts define Claude's behavior, capabilities, and response style. The Elixir SDK provides several ways to customize system prompts: using CLAUDE.md files for project-level instructions, output styles for persistent configurations, appending to the default prompt, passing settings directly, or using a fully custom prompt.

## Understanding system prompts

A system prompt is the initial instruction set that shapes how Claude behaves throughout a conversation.

> **Default behavior:** The Agent SDK uses a **minimal system prompt** by default. It contains only essential tool instructions but omits Claude Code's coding guidelines, response style, and project context. To customize behavior, use `:system_prompt` to replace the default entirely, or `:append_system_prompt` to add instructions while keeping the defaults.

Claude Code's system prompt includes:

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

### Method 2: Output styles (persistent configurations)

Output styles are saved configurations that modify Claude's system prompt. They are stored as markdown files and can be reused across sessions and projects.

#### Creating an output style

Output style files are markdown files with YAML frontmatter, stored in `~/.claude/output-styles/` (user-level) or `.claude/output-styles/` (project-level):

```markdown
---
name: Code Reviewer
description: Thorough code review assistant
keep-coding-instructions: true
---

You are an expert code reviewer.

For every code submission:
1. Check for bugs and security issues
2. Evaluate performance
3. Suggest improvements
4. Rate code quality (1-10)
```

Supported frontmatter fields:

| Field | Purpose | Default |
|:------|:--------|:--------|
| `name` | Name of the output style, if not the file name | Inherits from file name |
| `description` | Description shown in the UI of `/output-style` | None |
| `keep-coding-instructions` | Whether to keep the parts of Claude Code's system prompt related to coding | false |

#### Using output styles

Once created, activate output styles via:

- **CLI**: `/output-style [style-name]`
- **Settings**: `.claude/settings.local.json`
- **Create new**: `/output-style:new [description]`

Output styles are loaded when you include `"user"` or `"project"` in your `:setting_sources` option:

```elixir
{:ok, result} = ClaudeCode.query("Review this module for issues",
  setting_sources: ["user"]
)
```

#### When to use output styles

**Best for:**

- Persistent behavior changes across sessions
- Team-shared configurations
- Specialized assistants (code reviewer, data scientist, DevOps)
- Complex prompt modifications that need versioning

**Examples:**

- Creating a dedicated SQL optimization assistant
- Building a security-focused code reviewer
- Developing a teaching assistant with specific pedagogy

### Method 3: Appending to the system prompt

Use `:append_system_prompt` to add your custom instructions while preserving all built-in functionality. This is the recommended approach for most use cases.

```elixir
{:ok, result} = ClaudeCode.query("Help me process this large CSV file",
  append_system_prompt: "Focus on performance optimization. Prefer Stream over Enum for large datasets."
)
```

This keeps Claude's tool-usage instructions, safety guidelines, and environment context intact while adding your custom behavior.

### Method 4: Custom system prompts

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

### Method 5: Settings configuration

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

## Comparison of approaches

| Feature | CLAUDE.md | Output Styles | `:append_system_prompt` | Custom `:system_prompt` | `:settings` |
|:--------|:----------|:--------------|:------------------------|:------------------------|:------------|
| **Persistence** | Per-project file | Saved as files | Session only | Session only | Session only |
| **Reusability** | Per-project | Across projects | Code duplication | Code duplication | File or code |
| **Management** | On filesystem | CLI + files | In code | In code | In code |
| **Default tools** | Preserved | Preserved | Preserved | Lost (unless included) | Preserved |
| **Built-in safety** | Maintained | Maintained | Maintained | Must be added | Maintained |
| **Environment context** | Automatic | Automatic | Automatic | Must be provided | Automatic |
| **Customization level** | Additions only | Replace default | Additions only | Complete control | Key-value config |
| **Version control** | With project | Yes | With code | With code | File or code |
| **Scope** | Project-specific | User or project | Code session | Code session | Code session |

## Use cases and best practices

### When to use CLAUDE.md

**Best for:**

- Project-specific coding standards and conventions
- Documenting project structure and architecture
- Listing common commands (build, test, deploy)
- Team-shared context that should be version controlled
- Instructions that apply to all SDK usage in a project

**Important:** The SDK only reads CLAUDE.md files when you explicitly include `"project"` or `"user"` in `:setting_sources`.

### When to use output styles

**Best for:**

- Persistent behavior changes across sessions
- Team-shared configurations
- Specialized assistants (code reviewer, data scientist, DevOps)
- Complex prompt modifications that need versioning

**Examples:**

- Creating a dedicated SQL optimization assistant
- Building a security-focused code reviewer
- Developing a teaching assistant with specific pedagogy

### When to use `:append_system_prompt`

**Best for:**

- Adding specific coding standards or preferences
- Customizing output formatting
- Adding domain-specific knowledge
- Modifying response verbosity
- Enhancing Claude Code's default behavior without losing tool instructions

### When to use custom `:system_prompt`

**Best for:**

- Complete control over Claude's behavior
- Specialized single-session tasks
- Testing new prompt strategies
- Situations where default tools are not needed
- Building specialized agents with unique behavior

## Combining approaches

You can combine these methods for maximum flexibility:

```elixir
# Assuming an output style is active (via /output-style),
# add session-specific focus areas
{:ok, result} = ClaudeCode.query("Review this authentication module",
  append_system_prompt: """
  For this review, prioritize:
  - OAuth 2.0 compliance
  - Token storage security
  - Session management
  """,
  setting_sources: ["project"]
)
```

## See also

- [Output styles](https://code.claude.com/docs/en/output-styles) -- Complete output styles documentation
- [Permissions](permissions.md) -- Control tool access
- [Subagents](subagents.md) -- Custom agent definitions with specialized prompts
- [Sessions](sessions.md) -- Session management and multi-turn conversations
