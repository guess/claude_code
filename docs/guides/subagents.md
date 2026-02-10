# Subagents

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/subagents). Examples are adapted for Elixir.

Define and invoke subagents to isolate context, run tasks in parallel, and apply specialized instructions.

## Overview

Subagents are separate agent instances that your main agent can spawn to handle focused subtasks. Use subagents to:

- **Isolate context** for focused subtasks without bloating the main prompt
- **Run multiple analyses in parallel** (e.g., style check + security scan simultaneously)
- **Apply specialized instructions** with tailored system prompts and tool restrictions

You can create subagents in three ways:

| Method | Description |
|--------|-------------|
| **Programmatic** | Use `ClaudeCode.Agent` structs with the `agents` option in `start_link/1` or `stream/3` (recommended for SDK applications) |
| **Filesystem-based** | Define agents as markdown files in `.claude/agents/` directories |
| **Built-in** | Claude can invoke the built-in `general-purpose` subagent via the Task tool without any configuration |

This guide focuses on the programmatic approach.

## How agents are delivered

Agent configurations are sent to the CLI via the **control protocol initialize handshake**, not as CLI flags. When a session starts, the adapter sends an `initialize` control request that includes the agents map. This matches the behavior of the Python/TypeScript Agent SDKs.

## Creating subagents

Define subagents using `ClaudeCode.Agent` structs and the `agents` option. The `Task` tool must be in `allowed_tools` since Claude invokes subagents through it.

```elixir
alias ClaudeCode.Agent

{:ok, session} = ClaudeCode.start_link(
  agents: [
    Agent.new(
      name: "code-reviewer",
      # description tells Claude when to use this subagent
      description: "Expert code review specialist. Use for quality, security, and maintainability reviews.",
      # prompt defines the subagent's behavior and expertise
      prompt: """
      You are a code review specialist with expertise in security, performance, and Elixir best practices.

      When reviewing code:
      - Identify security vulnerabilities
      - Check for performance issues
      - Verify adherence to coding standards
      - Suggest specific improvements
      """,
      # tools restricts what the subagent can do (read-only here)
      tools: ["Read", "Grep", "Glob"],
      # model overrides the default model for this subagent
      model: "sonnet"
    ),
    Agent.new(
      name: "test-runner",
      description: "Runs and analyzes test suites. Use for test execution and coverage analysis.",
      prompt: """
      You are a test execution specialist. Run tests and provide clear analysis of results.

      Focus on:
      - Running test commands
      - Analyzing test output
      - Identifying failing tests
      - Suggesting fixes for failures
      """,
      # Bash access lets this subagent run test commands
      tools: ["Bash", "Read", "Grep"]
    )
  ],
  # Task tool is required for subagent invocation
  allowed_tools: ["Read", "Grep", "Glob", "Task"]
)
```

### Agent fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique agent identifier |
| `description` | string | Recommended | When to use this agent. Claude matches tasks to agents based on this. |
| `prompt` | string | Recommended | System prompt defining the agent's role and behavior |
| `tools` | list | No | Tools the agent can use. If omitted, inherits all tools. |
| `model` | string | No | Model override: `"sonnet"`, `"opus"`, `"haiku"`, or `"inherit"`. Defaults to session model. |

> Subagents cannot spawn their own subagents. Don't include `"Task"` in a subagent's `tools` list.

## Invoking subagents

### Automatic invocation

Claude automatically decides when to invoke subagents based on the task and each subagent's `"description"`. Write clear, specific descriptions so Claude can match tasks to the right subagent.

```elixir
# Claude will automatically delegate to the code-reviewer agent
session
|> ClaudeCode.stream("Review the authentication module for security issues")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

### Explicit invocation

To guarantee Claude uses a specific subagent, mention it by name in your prompt:

```elixir
session
|> ClaudeCode.stream("Use the code-reviewer agent to check the authentication module")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

### Dynamic agent configuration

Create agent definitions dynamically based on runtime conditions:

```elixir
defmodule MyApp.Agents do
  alias ClaudeCode.Agent

  def security_reviewer(level) do
    strict? = level == :strict

    Agent.new(
      name: "security-reviewer",
      description: "Security code reviewer",
      prompt: if(strict?,
        do: "You are a strict security reviewer. Flag all potential issues, even minor ones.",
        else: "You are a balanced security reviewer. Focus on critical and high-severity issues."
      ),
      tools: ["Read", "Grep", "Glob"],
      # Use a more capable model for strict reviews
      model: if(strict?, do: "opus", else: "sonnet")
    )
  end
end

# The agent is created at session time, so each session can use different settings
{:ok, session} = ClaudeCode.start_link(
  agents: [MyApp.Agents.security_reviewer(:strict)],
  allowed_tools: ["Read", "Grep", "Glob", "Task"]
)
```

## Detecting subagent invocation

Subagents are invoked via the Task tool. Check for `tool_use` blocks with `name: "Task"`. Messages from within a subagent's context include a `parent_tool_use_id` field.

```elixir
session
|> ClaudeCode.stream("Review the code and write tests for lib/my_app.ex")
|> Stream.each(fn
  %ClaudeCode.Message.AssistantMessage{message: %{content: blocks}} ->
    Enum.each(blocks, fn
      %ClaudeCode.Content.ToolUseBlock{name: "Task", input: input} ->
        IO.puts("Subagent invoked: #{input["subagent_type"]}")
      _ -> :ok
    end)

  %{parent_tool_use_id: id} when not is_nil(id) ->
    IO.puts("  (running inside subagent)")

  _ -> :ok
end)
|> Stream.run()
```

## Per-query agent overrides

Override agent definitions for specific queries:

```elixir
session
|> ClaudeCode.stream("Review this module",
     agents: [
       Agent.new(
         name: "code-reviewer",
         description: "Security-focused code reviewer",
         prompt: "Focus exclusively on security vulnerabilities and OWASP issues.",
         tools: ["Read", "Grep"]
       )
     ])
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

## Using the `agent` option

Select a specific agent for the entire session:

```elixir
{:ok, session} = ClaudeCode.start_link(
  agents: [
    Agent.new(
      name: "reviewer",
      description: "Code reviewer",
      prompt: "You review code for quality."
    )
  ],
  agent: "reviewer"
)
```

## Tool restrictions

Subagents can have restricted tool access via the `"tools"` field:

- **Omit the field**: agent inherits all available tools (default)
- **Specify tools**: agent can only use listed tools

### Common tool combinations

| Use case | Tools | Description |
|----------|-------|-------------|
| Read-only analysis | `Read`, `Grep`, `Glob` | Can examine code but not modify or execute |
| Test execution | `Bash`, `Read`, `Grep` | Can run commands and analyze output |
| Code modification | `Read`, `Edit`, `Write`, `Grep`, `Glob` | Full read/write access without command execution |
| Full access | _(omit field)_ | Inherits all tools from parent |

## Troubleshooting

### Claude not delegating to subagents

1. **Include the Task tool**: subagents are invoked via the Task tool, so it must be in `allowed_tools`
2. **Use explicit prompting**: mention the subagent by name (e.g., "Use the code-reviewer agent to...")
3. **Write a clear description**: explain exactly when the subagent should be used

### Subagents not spawning their own subagents

This is by design. Don't include `"Task"` in a subagent's `"tools"` list.

## Next Steps

- [Custom Tools](custom-tools.md) - Build tools with Hermes MCP
- [Modifying System Prompts](modifying-system-prompts.md) - Customize agent behavior
- [Permissions](permissions.md) - Control tool access per agent
