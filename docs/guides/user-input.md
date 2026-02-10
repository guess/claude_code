# User Approvals and Input

Programmatic tool approval, multi-turn conversations, and interactive sessions.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/user-input). Examples are adapted for Elixir.

## Programmatic Tool Approval

The `:can_use_tool` option lets you approve or reject tool calls before they execute. This replaces the interactive permission prompt with your own logic.

### Read-only mode

Restrict Claude to read-only tools:

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: fn %{tool_name: name}, _id ->
    if name in ["Read", "Glob", "Grep"], do: :allow, else: {:deny, "Read-only mode"}
  end
)

session
|> ClaudeCode.stream("Summarize the README")
|> ClaudeCode.Stream.final_text()
```

### Interactive approval

Prompt a human operator for each tool call:

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: fn %{tool_name: name, input: input}, _id ->
    IO.puts("Tool: #{name}")
    IO.puts("Input: #{inspect(input)}")

    case IO.gets("Allow? [y/n] ") |> String.trim() do
      "y" -> :allow
      _ -> {:deny, "User rejected"}
    end
  end
)
```

### Module-based approval

For more complex logic, implement the `ClaudeCode.Hook` behaviour:

```elixir
defmodule MyApp.ToolPermissions do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{tool_name: "Bash", input: %{"command" => cmd}}, _tool_use_id) do
    cond do
      String.contains?(cmd, "rm -rf") -> {:deny, "Destructive command blocked"}
      String.starts_with?(cmd, "sudo") -> {:deny, "No sudo allowed"}
      true -> :allow
    end
  end

  def call(_input, _tool_use_id), do: :allow
end

{:ok, session} = ClaudeCode.start_link(can_use_tool: MyApp.ToolPermissions)
```

See the [Hooks guide](hooks.md) for the full `:can_use_tool` API including input rewriting and return value reference.

## Multi-Turn Conversations

Sessions maintain conversation context automatically. Each call to `ClaudeCode.stream/3` continues the conversation:

```elixir
{:ok, session} = ClaudeCode.start_link()

# Turn 1
session
|> ClaudeCode.stream("What is the Fibonacci sequence?")
|> ClaudeCode.Stream.final_text()
|> IO.puts()

# Turn 2 - Claude remembers the context
session
|> ClaudeCode.stream("Write an Elixir function that generates the first N numbers")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

# Turn 3
session
|> ClaudeCode.stream("Now add memoization")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stop(session)
```

## Interactive Loop

Build a simple REPL-style interaction:

```elixir
{:ok, session} = ClaudeCode.start_link(
  system_prompt: "You are a helpful coding assistant."
)

defmodule ChatLoop do
  def run(session) do
    case IO.gets("You: ") do
      :eof -> :ok
      {:error, _} -> :ok
      input ->
        prompt = String.trim(input)

        unless prompt == "" do
          IO.write("Claude: ")

          session
          |> ClaudeCode.stream(prompt)
          |> ClaudeCode.Stream.text_content()
          |> Enum.each(&IO.write/1)

          IO.puts("")
        end

        run(session)
    end
  end
end

ChatLoop.run(session)
ClaudeCode.stop(session)
```

## Health Checking

Check if a session's CLI subprocess is healthy:

```elixir
case ClaudeCode.health(session) do
  :healthy ->
    IO.puts("Session is ready")

  {:unhealthy, reason} ->
    IO.puts("Session is unhealthy: #{inspect(reason)}")
end
```

## Next Steps

- [Hooks](hooks.md) -- Lifecycle hooks, audit logging, and budget guards
- [Sessions](sessions.md) -- Resume, fork, and manage conversation history
- [Permissions](permissions.md) -- Static permission modes and tool restrictions
