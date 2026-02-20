# Slash Commands

Learn how to use slash commands to control Claude Code sessions through the SDK.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/slash-commands). Examples are adapted for Elixir.

Slash commands provide a way to control Claude Code sessions with special commands that start with `/`. These commands can be sent through the SDK to perform actions like clearing conversation history, compacting messages, or getting help.

## Discovering available slash commands

The `ClaudeCode.Message.SystemMessage` emitted at session initialization includes a `slash_commands` field listing all available commands (both built-in and custom). Access this information when your session starts:

```elixir
alias ClaudeCode.Message.SystemMessage

session
|> ClaudeCode.stream("Hello Claude")
|> Enum.each(fn
  %SystemMessage{subtype: :init, slash_commands: commands} ->
    IO.inspect(commands, label: "Available slash commands")
    # Example output: ["/compact", "/clear", "/help"]

  _ ->
    :ok
end)
```

The `slash_commands` field is a list of strings (`[String.t()]`), each prefixed with `/`.

## Sending slash commands

Send slash commands by passing them as the prompt string to `ClaudeCode.query/2` or `ClaudeCode.stream/3`, just like regular text. The CLI recognizes the `/` prefix and executes the command instead of treating it as a conversation prompt.

```elixir
alias ClaudeCode.Message.ResultMessage

# Send a slash command and get the result
result =
  session
  |> ClaudeCode.stream("/compact")
  |> ClaudeCode.Stream.final_result()

case result do
  %ResultMessage{is_error: false, result: text} ->
    IO.puts("Command executed: #{text}")

  %ResultMessage{is_error: true, result: error} ->
    IO.puts("Command failed: #{error}")
end
```

## Common slash commands

### `/compact` - Compact conversation history

The `/compact` command reduces the size of your conversation history by summarizing older messages while preserving important context. When the CLI compacts the conversation, it emits a `ClaudeCode.Message.CompactBoundaryMessage` with metadata about the compaction:

```elixir
alias ClaudeCode.Message.CompactBoundaryMessage
alias ClaudeCode.Message.ResultMessage

session
|> ClaudeCode.stream("/compact")
|> Enum.each(fn
  %CompactBoundaryMessage{compact_metadata: metadata} ->
    IO.puts("Compaction completed")
    IO.puts("Trigger: #{metadata.trigger}")
    IO.puts("Pre-compaction tokens: #{metadata.pre_tokens}")

  %ResultMessage{result: text} ->
    IO.puts("Result: #{text}")

  _ ->
    :ok
end)
```

The `ClaudeCode.Message.CompactBoundaryMessage` struct contains:

| Field              | Type                | Description                                                                                    |
| :----------------- | :------------------ | :--------------------------------------------------------------------------------------------- |
| `type`             | `:system`           | Always `:system`                                                                               |
| `subtype`          | `:compact_boundary` | Identifies this as a compaction boundary                                                       |
| `session_id`       | `String.t()`        | The current session ID                                                                         |
| `uuid`             | `String.t()`        | Unique identifier for this message                                                             |
| `compact_metadata` | `map()`             | Contains `:trigger` (`"manual"` or `"auto"`) and `:pre_tokens` (token count before compaction) |

Compaction can also happen automatically when the conversation approaches the context window limit. Automatic compaction emits the same `ClaudeCode.Message.CompactBoundaryMessage` with `trigger: "auto"`.

### `/clear` - Clear conversation

The `/clear` command starts a fresh conversation by clearing all previous history. After clearing, a new `ClaudeCode.Message.SystemMessage` with `subtype: :init` is emitted with a new session ID:

```elixir
alias ClaudeCode.Message.SystemMessage

session
|> ClaudeCode.stream("/clear")
|> Enum.each(fn
  %SystemMessage{subtype: :init, session_id: session_id} ->
    IO.puts("Conversation cleared, new session started")
    IO.puts("Session ID: #{session_id}")

  _ ->
    :ok
end)
```

## Creating custom slash commands

In addition to using built-in slash commands, you can create your own custom commands that are available through the SDK. Custom commands are defined as markdown files in specific directories, similar to how subagents are configured.

### File locations

Custom slash commands are stored in designated directories based on their scope:

- **Project commands**: `.claude/commands/` - Available only in the current project
- **Personal commands**: `~/.claude/commands/` - Available across all your projects

### File format

Each custom command is a markdown file where:

- The filename (without `.md` extension) becomes the command name
- The file content defines what the command does
- Optional YAML frontmatter provides configuration

#### Basic example

Create `.claude/commands/refactor.md`:

```markdown
Refactor the selected code to improve readability and maintainability.
Focus on clean code principles and best practices.
```

This creates the `/refactor` command that you can use through the SDK.

#### With frontmatter

Create `.claude/commands/security-check.md`:

```markdown
---
allowed-tools: Read, Grep, Glob
description: Run security vulnerability scan
model: claude-opus-4-6
---

Analyze the codebase for security vulnerabilities including:

- SQL injection risks
- XSS vulnerabilities
- Exposed credentials
- Insecure configurations
```

### Using custom commands in the SDK

Once defined in the filesystem, custom commands are automatically available through the SDK. They appear alongside built-in commands in the `slash_commands` list and are invoked the same way:

```elixir
alias ClaudeCode.Message.SystemMessage
alias ClaudeCode.Message.ResultMessage

# Custom commands appear in the slash_commands list
session
|> ClaudeCode.stream("Hello")
|> Enum.each(fn
  %SystemMessage{subtype: :init, slash_commands: commands} ->
    IO.inspect(commands)
    # Example: ["/compact", "/clear", "/help", "/refactor", "/security-check"]

  _ ->
    :ok
end)

# Invoke a custom command
result =
  session
  |> ClaudeCode.stream("/security-check", max_turns: 5)
  |> ClaudeCode.Stream.final_result()

IO.puts(result)
```

### Advanced features

#### Arguments and placeholders

Custom commands support dynamic arguments using numbered placeholders (`$1`, `$2`) and the `$ARGUMENTS` placeholder for the full argument string:

Create `.claude/commands/fix-issue.md`:

```markdown
---
argument-hint: [issue-number] [priority]
description: Fix a GitHub issue
---

Fix issue #$1 with priority $2.
Check the issue description and implement the necessary changes.
```

Send arguments after the command name:

```elixir
# $1 = "123", $2 = "high"
result =
  session
  |> ClaudeCode.stream("/fix-issue 123 high", max_turns: 5)
  |> ClaudeCode.Stream.final_result()

IO.puts(result)
```

#### Bash command execution

Custom commands can execute bash commands inline and include their output as context. Prefix a command with `!` inside backticks:

Create `.claude/commands/git-commit.md`:

```markdown
---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*)
description: Create a git commit
---

## Context

- Current status: !`git status`
- Current diff: !`git diff HEAD`

## Task

Create a git commit with appropriate message based on the changes.
```

#### File references

Include file contents in your command prompt using the `@` prefix:

Create `.claude/commands/review-config.md`:

```markdown
---
description: Review configuration files
---

Review the following configuration files for issues:

- Mix config: @config/config.exs
- Runtime config: @config/runtime.exs
- Environment: @.env.example

Check for security issues, outdated dependencies, and misconfigurations.
```

### Organization with namespacing

Organize commands in subdirectories for better structure:

```bash
.claude/commands/
├── frontend/
│   ├── component.md      # Creates /component (project:frontend)
│   └── style-check.md    # Creates /style-check (project:frontend)
├── backend/
│   ├── api-test.md       # Creates /api-test (project:backend)
│   └── db-migrate.md     # Creates /db-migrate (project:backend)
└── review.md             # Creates /review (project)
```

The subdirectory appears in the command description but doesn't affect the command name itself.

### Practical examples

#### Code review command

Create `.claude/commands/code-review.md`:

```markdown
---
allowed-tools: Read, Grep, Glob, Bash(git diff:*)
description: Comprehensive code review
---

## Changed Files

!`git diff --name-only HEAD~1`

## Detailed Changes

!`git diff HEAD~1`

## Review Checklist

Review the above changes for:

1. Code quality and readability
2. Security vulnerabilities
3. Performance implications
4. Test coverage
5. Documentation completeness

Provide specific, actionable feedback organized by priority.
```

#### Test runner command

Create `.claude/commands/test.md`:

```markdown
---
allowed-tools: Bash, Read, Edit
argument-hint: [test-pattern]
description: Run tests with optional pattern
---

Run tests matching pattern: $ARGUMENTS

1. Detect the test framework
2. Run tests with the provided pattern
3. If tests fail, analyze and fix them
4. Re-run to verify fixes
```

Use these commands through the SDK:

```elixir
# Run code review
result =
  session
  |> ClaudeCode.stream("/code-review", max_turns: 3)
  |> ClaudeCode.Stream.final_result()

# Run specific tests
result =
  session
  |> ClaudeCode.stream("/test auth", max_turns: 5)
  |> ClaudeCode.Stream.final_result()
```

## Disabling slash commands

To disable all slash commands (both built-in and custom), use the `disable_slash_commands` option:

```elixir
{:ok, session} = ClaudeCode.start_link(
  disable_slash_commands: true
)
```

This can also be set at the query level:

```elixir
result =
  session
  |> ClaudeCode.stream("Hello", disable_slash_commands: true)
  |> ClaudeCode.Stream.final_result()
```

## See also

- [Slash Commands](https://code.claude.com/docs/en/slash-commands) - Complete slash command documentation
- [Subagents](subagents.md) - Similar filesystem-based configuration for subagents
- [Modifying System Prompts](modifying-system-prompts.md) - Customize Claude's behavior with system prompts
- [Sessions](sessions.md) - Session management and multi-turn conversations
- [CLI Reference](https://code.claude.com/docs/en/cli-reference) - Command-line interface
