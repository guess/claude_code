# Subagents

Define custom agents that Claude can delegate tasks to during a conversation.

## Defining Agents

Use the `agents` option to define specialized agents:

```elixir
{:ok, session} = ClaudeCode.start_link(
  agents: %{
    "code-reviewer" => %{
      "description" => "Reviews code for quality, style, and potential bugs",
      "prompt" => "You are an expert code reviewer. Focus on correctness, readability, and Elixir idioms.",
      "tools" => ["Read", "Glob", "Grep"],
      "model" => "sonnet"
    },
    "test-writer" => %{
      "description" => "Writes ExUnit tests for Elixir modules",
      "prompt" => "You write comprehensive ExUnit tests. Include edge cases and property-based tests.",
      "tools" => ["Read", "Write", "Bash(mix:*)"],
      "model" => "sonnet"
    }
  },
  # Allow Claude to use the Task tool to invoke subagents
  allowed_tools: ["Read", "Edit", "Write", "Bash", "Task"]
)
```

## Agent Definition Fields

| Field | Required | Description |
|-------|----------|-------------|
| `"description"` | Yes | Short description of what the agent does. Claude uses this to decide when to invoke it. |
| `"prompt"` | Yes | System prompt for the agent. Defines its behavior and expertise. |
| `"tools"` | No | List of tools the agent can use. Defaults to all available tools. |
| `"model"` | No | Claude model for the agent. Defaults to the session's model. |

## How Agents Work

When Claude receives a task that matches an agent's description, it uses the `Task` tool to delegate:

1. Claude sees the available agents and their descriptions
2. For a matching task, Claude invokes `Task` with the agent name and a prompt
3. The agent runs with its own system prompt and tool set
4. The agent's result is returned to the main conversation

## Allowing Agent Invocation

Ensure `Task` is in the allowed tools for the main session:

```elixir
{:ok, session} = ClaudeCode.start_link(
  agents: %{"reviewer" => %{...}},
  allowed_tools: ["Read", "Edit", "Task"]  # Task is required
)
```

## Detecting Agent Invocation in a Stream

Watch for `Task` tool usage to track when agents are invoked:

```elixir
session
|> ClaudeCode.stream("Review the code and write tests for lib/my_app.ex")
|> ClaudeCode.Stream.on_tool_use(fn tool ->
  if tool.name == "Task" do
    IO.puts("Delegating to agent: #{inspect(tool.input)}")
  end
end)
|> ClaudeCode.Stream.collect()
```

## Per-Query Agent Overrides

Override agent definitions for specific queries:

```elixir
session
|> ClaudeCode.stream("Review this module",
     agents: %{
       "code-reviewer" => %{
         "description" => "Security-focused code reviewer",
         "prompt" => "Focus exclusively on security vulnerabilities and OWASP issues.",
         "tools" => ["Read", "Grep"]
       }
     })
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)
```

## Using the `agent` Option

Select a specific agent for the entire session:

```elixir
{:ok, session} = ClaudeCode.start_link(
  agents: %{
    "reviewer" => %{
      "description" => "Code reviewer",
      "prompt" => "You review code for quality."
    }
  },
  agent: "reviewer"
)
```

## Next Steps

- [Custom Tools](custom-tools.md) - Build tools with Hermes MCP
- [Modifying System Prompts](modifying-system-prompts.md) - Customize agent behavior
- [Permissions](permissions.md) - Control tool access per agent
