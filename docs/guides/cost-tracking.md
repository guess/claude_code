# Tracking Costs and Usage

Understand and track token usage for billing in the ClaudeCode SDK.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/cost-tracking). Examples are adapted for Elixir.

## Understanding Token Usage

When Claude processes requests, it reports token usage at the message level. This usage data is essential for tracking costs and billing users appropriately.

### Key Concepts

1. **Steps**: A step is a single request/response pair between your application and Claude
2. **Messages**: Individual messages within a step (text, tool uses, tool results)
3. **Usage**: Token consumption data attached to assistant messages

## Usage Reporting Structure

### Single vs Parallel Tool Use

When Claude executes tools, the usage reporting differs based on whether tools are executed sequentially or in parallel:

```elixir
alias ClaudeCode.Message.AssistantMessage

# Tracking usage in a conversation
session
|> ClaudeCode.stream("Analyze this codebase and run tests")
|> Enum.each(fn
  %AssistantMessage{message: %{id: id, usage: usage}} ->
    IO.puts("Message ID: #{id}")
    IO.inspect(usage, label: "Usage")

  _ ->
    :ok
end)
```

### Message Flow Example

Here's how messages and usage are reported in a typical multi-step conversation:

```
# Step 1: Initial request with parallel tool uses
assistant (text)      %{id: "msg_1", usage: %{output_tokens: 100, ...}}
assistant (tool_use)  %{id: "msg_1", usage: %{output_tokens: 100, ...}}
assistant (tool_use)  %{id: "msg_1", usage: %{output_tokens: 100, ...}}
assistant (tool_use)  %{id: "msg_1", usage: %{output_tokens: 100, ...}}
user (tool_result)
user (tool_result)
user (tool_result)

# Step 2: Follow-up response
assistant (text)      %{id: "msg_2", usage: %{output_tokens: 98, ...}}
```

## Important Usage Rules

### 1. Same ID = Same Usage

**All messages with the same `id` field report identical usage.** When Claude sends multiple messages in the same turn (e.g., text + tool uses), they share the same message ID and usage data.

```elixir
alias ClaudeCode.Message.AssistantMessage

# All these assistant messages have the same ID and usage.
# Charge only once per unique message ID.
session
|> ClaudeCode.stream("Complex task")
|> Enum.reduce(%{}, fn
  %AssistantMessage{message: %{id: id, usage: usage}}, seen ->
    if Map.has_key?(seen, id) do
      seen
    else
      IO.puts("Step #{map_size(seen) + 1} — #{usage.output_tokens} output tokens")
      Map.put(seen, id, usage)
    end

  _, seen ->
    seen
end)
```

### 2. Charge Once Per Step

**You should only charge users once per step**, not for each individual message. When you see multiple assistant messages with the same ID, use the usage from any one of them.

### 3. Result Message Contains Cumulative Usage

The final `ClaudeCode.Message.ResultMessage` contains the total cumulative usage from all steps in the conversation:

```elixir
result = session
|> ClaudeCode.stream("Multi-step task")
|> ClaudeCode.Stream.final_result()

IO.puts("Total cost: $#{result.total_cost_usd}")
IO.inspect(result.usage, label: "Total usage")
```

### 4. Per-Model Usage Breakdown

The `model_usage` field on `ClaudeCode.Message.ResultMessage` provides authoritative per-model usage data. Like `total_cost_usd`, this field is accurate and suitable for billing purposes. This is especially useful when using multiple models (e.g., Haiku for subagents, Opus for the main agent).

```elixir
result = session
|> ClaudeCode.stream("Complex task")
|> ClaudeCode.Stream.final_result()

Enum.each(result.model_usage, fn {model, usage} ->
  IO.puts("#{model}: $#{usage.cost_usd}")
  IO.puts("  Input tokens: #{usage.input_tokens}")
  IO.puts("  Output tokens: #{usage.output_tokens}")
  IO.puts("  Cache read: #{usage.cache_read_input_tokens}")
  IO.puts("  Web searches: #{usage.web_search_requests}")
end)
```

## Implementation: Cost Tracking System

Here's a complete example of implementing a cost tracking system using an OTP Agent:

```elixir
defmodule CostTracker do
  @moduledoc """
  Tracks per-step and cumulative costs across Claude conversations.
  Deduplicates usage by message ID to avoid double-counting parallel tool uses.
  """

  use Agent

  alias ClaudeCode.Message.{AssistantMessage, ResultMessage}

  defstruct processed_ids: MapSet.new(), step_usages: [], total_cost: 0.0

  def start_link(_opts) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  @doc "Process an assistant message, deduplicating by message ID."
  def process_message(%AssistantMessage{message: %{id: id, usage: usage}})
      when is_binary(id) do
    Agent.update(__MODULE__, fn state ->
      if MapSet.member?(state.processed_ids, id) do
        state
      else
        %{
          state
          | processed_ids: MapSet.put(state.processed_ids, id),
            step_usages: state.step_usages ++ [%{message_id: id, usage: usage}]
        }
      end
    end)
  end

  def process_message(%ResultMessage{total_cost_usd: cost}) do
    Agent.update(__MODULE__, &%{&1 | total_cost: cost})
  end

  def process_message(_), do: :ok

  @doc "Return the tracked state."
  def summary do
    Agent.get(__MODULE__, fn state ->
      %{
        steps: length(state.step_usages),
        step_usages: state.step_usages,
        total_cost: state.total_cost
      }
    end)
  end
end

# Usage
{:ok, _} = CostTracker.start_link([])

session
|> ClaudeCode.stream("Analyze and refactor this code")
|> Stream.each(&CostTracker.process_message/1)
|> Stream.run()

summary = CostTracker.summary()
IO.puts("Steps processed: #{summary.steps}")
IO.puts("Total cost: $#{Float.round(summary.total_cost, 4)}")
```

## Cost Controls

### Max Turns

Limit the number of agentic turns to control costs:

```elixir
{:ok, session} = ClaudeCode.start_link(max_turns: 5)
```

If the limit is hit, the result will have `subtype: :error_max_turns`.

### Max Budget

Set a dollar amount limit per session:

```elixir
{:ok, session} = ClaudeCode.start_link(max_budget_usd: 0.50)
```

If the budget is exceeded, the result will have `subtype: :error_max_budget_usd`.

### Combining Limits

```elixir
{:ok, session} = ClaudeCode.start_link(
  max_turns: 10,
  max_budget_usd: 1.00,
  model: "sonnet"  # Choose a cost-effective model
)
```

## Handling Edge Cases

### Output Token Discrepancies

In rare cases, you might observe different `output_tokens` values for messages with the same ID. When this occurs:

1. **Use the highest value** - The final message in a group typically contains the accurate total
2. **Verify against total cost** - The `total_cost_usd` in the result message is authoritative
3. **Report inconsistencies** - File issues at the [Claude Code GitHub repository](https://github.com/anthropics/claude-code/issues)

### Cache Token Tracking

When using prompt caching, track these token types separately:

```elixir
# From result.usage
%{
  cache_creation_input_tokens: integer(),
  cache_read_input_tokens: integer(),
  cache_creation: %{
    ephemeral_5m_input_tokens: integer(),
    ephemeral_1h_input_tokens: integer()
  }
}
```

## Best Practices

1. **Use Message IDs for Deduplication**: Always track processed message IDs to avoid double-charging
2. **Monitor the Result Message**: Use `ClaudeCode.Stream.final_result/1` to get authoritative cumulative usage
3. **Implement Logging**: Log all usage data for auditing and debugging
4. **Handle Failures Gracefully**: Track partial usage even if a conversation fails
5. **Use Stream Processing**: Process usage as messages arrive with `Stream.each/2`

## Usage Fields Reference

Each usage map on `ClaudeCode.Message.ResultMessage` contains:

| Field                         | Description                                                          |
| ----------------------------- | -------------------------------------------------------------------- |
| `input_tokens`                | Base input tokens processed                                          |
| `output_tokens`               | Tokens generated in the response                                     |
| `cache_creation_input_tokens` | Tokens used to create cache entries                                  |
| `cache_read_input_tokens`     | Tokens read from cache                                               |
| `service_tier`                | The service tier used (e.g., `"standard"`)                           |
| `server_tool_use`             | Map with `web_search_requests` and `web_fetch_requests` counts       |
| `cache_creation`              | Map with `ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens` |

Each per-model usage entry in `model_usage` contains:

| Field                         | Description                  |
| ----------------------------- | ---------------------------- |
| `input_tokens`                | Input tokens for this model  |
| `output_tokens`               | Output tokens for this model |
| `cache_creation_input_tokens` | Cache creation tokens        |
| `cache_read_input_tokens`     | Cache read tokens            |
| `web_search_requests`         | Web search request count     |
| `cost_usd`                    | Cost in USD for this model   |
| `context_window`              | Context window size          |
| `max_output_tokens`           | Maximum output token limit   |

## Aggregating Costs Across Queries

Track costs across multiple queries in a session:

```elixir
{:ok, _} = CostTracker.start_link([])

for prompt <- ["Task 1", "Task 2", "Task 3"] do
  session
  |> ClaudeCode.stream(prompt)
  |> Stream.each(&CostTracker.process_message/1)
  |> Stream.run()
end

summary = CostTracker.summary()
IO.puts("Total session cost: $#{Float.round(summary.total_cost, 4)}")
```

## Next Steps

- [Stop Reasons](stop-reasons.md) - Understanding error subtypes
- [Hosting](hosting.md) - Production deployment
- [Secure Deployment](secure-deployment.md) - Budget and safety controls
