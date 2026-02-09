# Cost Tracking

Monitor token usage and API costs across your ClaudeCode sessions.

## Usage from ResultMessage

Every completed query returns usage and cost information in the `ResultMessage`:

```elixir
session
|> ClaudeCode.stream("Explain pattern matching")
|> Enum.each(fn
  %ClaudeCode.Message.ResultMessage{} = result ->
    IO.puts("Cost: $#{result.total_cost_usd}")
    IO.puts("Turns: #{result.num_turns}")
    IO.puts("Duration: #{result.duration_ms}ms")
    IO.puts("API time: #{result.duration_api_ms}ms")
    IO.puts("Input tokens: #{result.usage.input_tokens}")
    IO.puts("Output tokens: #{result.usage.output_tokens}")
    IO.puts("Cache read: #{result.usage.cache_read_input_tokens}")

  _ -> :ok
end)
```

## Using Stream.collect/1

`collect/1` provides a summary including the result metadata:

```elixir
summary = session
|> ClaudeCode.stream("Create a GenServer module")
|> ClaudeCode.Stream.collect()

IO.puts("Total cost: $#{summary.result && "see ResultMessage"}")
IO.puts("Tool calls: #{length(summary.tool_calls)}")
IO.puts("Is error: #{summary.is_error}")
```

For full cost details, capture the `ResultMessage` directly:

```elixir
result = session
|> ClaudeCode.stream("Analyze this codebase")
|> Enum.filter(&match?(%ClaudeCode.Message.ResultMessage{}, &1))
|> List.first()

if result do
  IO.puts("$#{Float.round(result.total_cost_usd, 4)}")
end
```

## Usage from SystemMessage

The `SystemMessage` (emitted at the start of each query) contains the model being used:

```elixir
session
|> ClaudeCode.stream("Hello")
|> Enum.each(fn
  %ClaudeCode.Message.SystemMessage{model: model} ->
    IO.puts("Using model: #{model}")
  _ -> :ok
end)
```

## Per-Model Usage

The `model_usage` field on `ResultMessage` breaks down usage by model:

```elixir
session
|> ClaudeCode.stream("Complex task")
|> Enum.each(fn
  %ClaudeCode.Message.ResultMessage{model_usage: model_usage} ->
    Enum.each(model_usage, fn {model, usage} ->
      IO.puts("#{model}: #{usage.input_tokens} in / #{usage.output_tokens} out ($#{usage.cost_usd})")
    end)
  _ -> :ok
end)
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

## Aggregating Costs

Track costs across multiple queries:

```elixir
defmodule CostTracker do
  use Agent

  def start_link(_), do: Agent.start_link(fn -> 0.0 end, name: __MODULE__)

  def track(result) do
    Agent.update(__MODULE__, &(&1 + result.total_cost_usd))
  end

  def total, do: Agent.get(__MODULE__, & &1)
end

# Usage
{:ok, _} = CostTracker.start_link(nil)

session
|> ClaudeCode.stream("Task 1")
|> Enum.each(fn
  %ClaudeCode.Message.ResultMessage{} = r -> CostTracker.track(r)
  _ -> :ok
end)

session
|> ClaudeCode.stream("Task 2")
|> Enum.each(fn
  %ClaudeCode.Message.ResultMessage{} = r -> CostTracker.track(r)
  _ -> :ok
end)

IO.puts("Total session cost: $#{Float.round(CostTracker.total(), 4)}")
```

## Next Steps

- [Stop Reasons](stop-reasons.md) - Understanding error subtypes
- [Hosting](hosting.md) - Production deployment
- [Secure Deployment](secure-deployment.md) - Budget and safety controls
