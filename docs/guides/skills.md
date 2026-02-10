# Agent Skills in the SDK

Extend Claude with specialized capabilities using Agent Skills.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/skills). Examples are adapted for Elixir.

Agent Skills extend Claude with specialized capabilities that Claude autonomously invokes when relevant. Skills are packaged as `SKILL.md` files containing instructions, descriptions, and optional supporting resources.

For comprehensive information about Skills, including benefits, architecture, and authoring guidelines, see the [Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview).

## How Skills work with the SDK

When using the ClaudeCode SDK, Skills are:

1. **Defined as filesystem artifacts** -- Created as `SKILL.md` files in specific directories (`.claude/skills/`)
2. **Loaded from filesystem** -- Skills are loaded from configured filesystem locations. You must specify `setting_sources` to load Skills from the filesystem
3. **Automatically discovered** -- Once filesystem settings are loaded, Skill metadata is discovered at startup from user and project directories; full content is loaded when triggered
4. **Model-invoked** -- Claude autonomously chooses when to use them based on context
5. **Enabled via allowed_tools** -- Add `"Skill"` to your `allowed_tools` to enable Skills

Unlike subagents (which can be defined programmatically), Skills must be created as filesystem artifacts. The SDK does not provide a programmatic API for registering Skills.

> **Default behavior:** By default, the SDK does not load any filesystem settings. To use Skills, you must explicitly configure `setting_sources: ["user", "project"]` in your options. You must also include `"Skill"` in `allowed_tools` or Skills will not be available.

## Using Skills with the SDK

To use Skills, you need to:

1. Include `"Skill"` in your `allowed_tools` configuration
2. Configure `setting_sources` to load Skills from the filesystem

Once configured, Claude automatically discovers Skills from the specified directories and invokes them when relevant to the user's request.

```elixir
alias ClaudeCode.Message.ResultMessage

{:ok, session} = ClaudeCode.start_link(
  cwd: "/path/to/project",                          # Project with .claude/skills/
  setting_sources: ["user", "project"],              # Load Skills from filesystem
  allowed_tools: ["Skill", "Read", "Write", "Bash"] # Enable Skill tool
)

result =
  session
  |> ClaudeCode.stream("Help me process this PDF document")
  |> ClaudeCode.Stream.final_result()

case result do
  %ResultMessage{is_error: false, result: text} ->
    IO.puts(text)

  %ResultMessage{is_error: true, result: error} ->
    IO.puts("Error: #{error}")
end
```

## Skill locations

Skills are loaded from filesystem directories based on your `setting_sources` configuration:

| Source | Directory | Loaded when |
| :----- | :-------- | :---------- |
| Project Skills | `.claude/skills/` (relative to `cwd`) | `setting_sources` includes `"project"` |
| User Skills | `~/.claude/skills/` | `setting_sources` includes `"user"` |
| Plugin Skills | Bundled with installed Claude Code plugins | Plugins are configured via the `plugins` option |

Use `setting_sources: ["user", "project"]` to load Skills from both personal and project directories.

## Creating Skills

Skills are defined as directories containing a `SKILL.md` file with YAML frontmatter and Markdown content. The `description` field in the frontmatter determines when Claude invokes your Skill.

Example directory structure:

```
.claude/skills/processing-pdfs/
  SKILL.md
```

Example `SKILL.md`:

```markdown
---
description: Extract text and data from PDF documents using poppler utilities
allowed-tools:
  - Bash
  - Read
  - Write
---

# PDF Processing

When asked to process a PDF document:

1. Use `pdftotext` to extract raw text
2. Parse the extracted text for structured data
3. Return the results in the requested format
```

For complete guidance on creating Skills, including multi-file Skills and examples, see:

- [Agent Skills in Claude Code](https://code.claude.com/docs/en/skills) -- Complete guide with examples
- [Agent Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) -- Authoring guidelines and naming conventions

## Tool restrictions

> The `allowed-tools` frontmatter field in `SKILL.md` is only supported when using the Claude Code CLI directly. **It does not apply when using Skills through the SDK.**
>
> When using the SDK, control tool access through the `allowed_tools` option in your session or query configuration.

To restrict which tools are available when Skills run, set the `allowed_tools` option:

```elixir
alias ClaudeCode.Message.ResultMessage

{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["user", "project"],          # Load Skills from filesystem
  allowed_tools: ["Skill", "Read", "Grep", "Glob"] # Restricted toolset
)

result =
  session
  |> ClaudeCode.stream("Analyze the codebase structure")
  |> ClaudeCode.Stream.final_result()

IO.puts(result.result)
```

## Discovering available Skills

To see which Skills are available, you can ask Claude directly or inspect the `ClaudeCode.Message.SystemMessage` emitted at the start of each query. The `skills` field on the system message contains the list of discovered Skill names.

### Asking Claude

```elixir
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["user", "project"],
  allowed_tools: ["Skill"]
)

result =
  session
  |> ClaudeCode.stream("What Skills are available?")
  |> ClaudeCode.Stream.final_result()

IO.puts(result.result)
```

### Inspecting the system message

```elixir
alias ClaudeCode.Message.SystemMessage

session
|> ClaudeCode.stream("Hello")
|> Enum.each(fn
  %SystemMessage{skills: skills} ->
    IO.puts("Available skills: #{inspect(skills)}")

  _ ->
    :ok
end)
```

The `skills` field on `ClaudeCode.Message.SystemMessage` is a `[String.t()]` list of Skill names discovered from the configured setting sources.

## Testing Skills

Test Skills by asking questions that match their descriptions. Claude automatically invokes the relevant Skill if the description matches your request:

```elixir
alias ClaudeCode.Message.ResultMessage

{:ok, session} = ClaudeCode.start_link(
  cwd: "/path/to/project",
  setting_sources: ["user", "project"],
  allowed_tools: ["Skill", "Read", "Bash"]
)

result =
  session
  |> ClaudeCode.stream("Extract text from invoice.pdf")
  |> ClaudeCode.Stream.final_result()

case result do
  %ResultMessage{is_error: false, result: text} ->
    IO.puts("Skill output:\n#{text}")

  %ResultMessage{is_error: true, result: error} ->
    IO.puts("Error: #{error}")
end
```

To verify that a Skill was actually invoked, use `ClaudeCode.Stream.tool_uses/1` to inspect tool calls in the stream:

```elixir
alias ClaudeCode.Content.ToolUseBlock

session
|> ClaudeCode.stream("Extract text from invoice.pdf")
|> ClaudeCode.Stream.tool_uses()
|> Enum.each(fn %ToolUseBlock{name: name, input: input} ->
  IO.puts("Tool called: #{name} with input: #{inspect(input)}")
end)
```

## Disabling Skills

Skills can be disabled using the `disable_slash_commands` option. This disables both Skills and slash commands:

```elixir
{:ok, session} = ClaudeCode.start_link(
  disable_slash_commands: true
)
```

> The `disable_slash_commands` option disables Skills as well as slash commands. There is no separate option to disable only Skills while keeping slash commands active.

## Troubleshooting

### Skills not found

**Check `setting_sources` configuration.** Skills are only loaded when you explicitly configure `setting_sources`. This is the most common issue:

```elixir
# Wrong -- Skills won't be loaded (no setting_sources)
{:ok, session} = ClaudeCode.start_link(
  allowed_tools: ["Skill"]
)

# Correct -- Skills will be loaded from filesystem
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["user", "project"],
  allowed_tools: ["Skill"]
)
```

**Check `allowed_tools` configuration.** Even with `setting_sources` configured, Skills require `"Skill"` in `allowed_tools`:

```elixir
# Wrong -- Skills are loaded but not enabled as a tool
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["user", "project"]
)

# Correct -- Skills are loaded and enabled
{:ok, session} = ClaudeCode.start_link(
  setting_sources: ["user", "project"],
  allowed_tools: ["Skill"]
)
```

**Check working directory.** The SDK loads project Skills relative to the `cwd` option. Ensure it points to a directory containing `.claude/skills/`:

```elixir
{:ok, session} = ClaudeCode.start_link(
  cwd: "/path/to/project",             # Must contain .claude/skills/
  setting_sources: ["user", "project"],
  allowed_tools: ["Skill"]
)
```

**Verify filesystem location:**

```bash
# Check project Skills
ls .claude/skills/*/SKILL.md

# Check personal Skills
ls ~/.claude/skills/*/SKILL.md
```

### Skill not being used

**Check the Skill tool is enabled.** Confirm `"Skill"` is in your `allowed_tools`.

**Check the description.** Ensure the `description` field in the SKILL.md frontmatter is specific and includes relevant keywords. Claude uses the description to decide when to invoke a Skill. See [Agent Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#writing-effective-descriptions) for guidance on writing effective descriptions.

### Additional troubleshooting

For general Skills troubleshooting (YAML syntax, debugging, etc.), see the [Claude Code Skills troubleshooting section](https://code.claude.com/docs/en/skills#troubleshooting).

## Next steps

- [Slash Commands](slash-commands.md) -- User-invoked commands (also loaded via `setting_sources`)
- [Subagents](subagents.md) -- Similar filesystem-based agents with programmatic options
- [Plugins](plugins.md) -- Plugin configuration and management
- [Modifying System Prompts](modifying-system-prompts.md) -- Customize Claude's behavior
