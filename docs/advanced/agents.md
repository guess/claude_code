# Custom Agents Guide

Custom agents allow you to define specialized AI assistants with specific behaviors, tools, and prompts.

## Basic Usage

Define agents when starting a session:

```elixir
agents = %{
  "code-reviewer" => %{
    "description" => "Expert code reviewer",
    "prompt" => "You are a senior developer. Review code for quality and best practices.",
    "tools" => ["View", "Grep", "Glob"],
    "model" => "sonnet"
  }
}

{:ok, session} = ClaudeCode.start_link(agents: agents)
```

## Agent Configuration

Each agent is a map with:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | Yes | Short description of the agent's purpose |
| `prompt` | string | Yes | System prompt defining agent behavior |
| `tools` | list | No | Tools the agent can use |
| `model` | string | No | Model to use ("sonnet", "opus", "haiku") |

## Example Agents

### Code Reviewer

```elixir
"code-reviewer" => %{
  "description" => "Reviews code for bugs, quality, and best practices",
  "prompt" => """
  You are a senior Elixir developer and code reviewer.
  Focus on:
  - Code quality and readability
  - Potential bugs and edge cases
  - Performance issues
  - Elixir best practices and idioms
  Provide specific, actionable feedback.
  """,
  "tools" => ["View", "Grep", "Glob"],
  "model" => "sonnet"
}
```

### Test Writer

```elixir
"test-writer" => %{
  "description" => "Generates comprehensive ExUnit tests",
  "prompt" => """
  You write comprehensive ExUnit tests.
  Include:
  - Happy path tests
  - Edge cases
  - Error conditions
  - Property-based tests when appropriate
  Follow Elixir testing conventions.
  """,
  "tools" => ["View", "Edit", "Grep"],
  "model" => "sonnet"
}
```

### Documentation Writer

```elixir
"doc-writer" => %{
  "description" => "Creates and improves documentation",
  "prompt" => """
  You write clear, concise documentation.
  Focus on:
  - Module and function docs
  - Usage examples
  - Type specifications
  Follow ExDoc conventions.
  """,
  "tools" => ["View", "Edit"],
  "model" => "haiku"
}
```

## Multiple Agents

Configure multiple agents in one session:

```elixir
agents = %{
  "reviewer" => %{
    "description" => "Code review",
    "prompt" => "You review code...",
    "tools" => ["View", "Grep"]
  },
  "tester" => %{
    "description" => "Test writing",
    "prompt" => "You write tests...",
    "tools" => ["View", "Edit"]
  },
  "documenter" => %{
    "description" => "Documentation",
    "prompt" => "You write docs...",
    "tools" => ["View", "Edit"]
  }
}

{:ok, session} = ClaudeCode.start_link(agents: agents)
```

## With Supervision

Use agents with supervised sessions:

```elixir
agents = %{
  "code-reviewer" => %{
    "description" => "Expert code reviewer",
    "prompt" => "You review Elixir code for quality.",
    "tools" => ["View", "Grep", "Glob"]
  }
}

{ClaudeCode.Supervisor, [
  [name: :reviewer, agents: agents],
  [name: :assistant]  # Without custom agents
]}
```

## Proactive Agents

The description field can indicate when agents should be used proactively:

```elixir
"code-reviewer" => %{
  "description" => "Expert code reviewer. Use proactively after code changes.",
  "prompt" => "..."
}
```

## Tool Restrictions

Agents inherit session tool restrictions but can have their own:

```elixir
agents = %{
  "safe-reviewer" => %{
    "description" => "Read-only code reviewer",
    "prompt" => "You review code without making changes.",
    "tools" => ["View", "Grep", "Glob"]  # No Edit or Write
  }
}

{:ok, session} = ClaudeCode.start_link(
  agents: agents,
  allowed_tools: ["View", "Grep", "Glob", "Edit"]  # Session allows Edit
  # But safe-reviewer agent only has View, Grep, Glob
)
```

## Model Selection

Use different models for different agents:

```elixir
agents = %{
  "complex-analyzer" => %{
    "description" => "Deep code analysis",
    "prompt" => "Perform thorough analysis...",
    "model" => "opus"  # Most capable
  },
  "quick-helper" => %{
    "description" => "Quick answers",
    "prompt" => "Provide brief, helpful responses.",
    "model" => "haiku"  # Fastest
  }
}
```

## Next Steps

- [Configuration Guide](configuration.md) - All configuration options
- [Supervision Guide](supervision.md) - Production patterns
