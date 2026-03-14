# Cost Tracking

Learn how to track token usage, deduplicate parallel tool calls, and calculate costs with the Claude Agent SDK.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/cost-tracking). Examples are adapted for Elixir.

The Claude Agent SDK provides detailed token usage information for each interaction with Claude. This guide explains how to properly track costs and understand usage reporting, especially when dealing with parallel tool uses and multi-step conversations.

## Understand Token Usage

Cost tracking depends on understanding how the SDK scopes usage data:

- **`query()` call:** one invocation of `ClaudeCode.query/2` or `ClaudeCode.stream/3`. A single call can involve multiple steps (Claude responds, uses tools, gets results, responds again). Each call produces one `ClaudeCode.Message.ResultMessage` at the end.
- **Step:** a single request/response cycle within a `query()` call. Each step produces assistant messages with token usage. When Claude uses multiple tools in one turn, all messages in that turn share the same `id`, so deduplicate by ID to avoid double-counting.
- **Session:** a series of `query()` calls linked by a session ID (using the `:resume` option). Each `query()` call within a session reports its own cost independently.

### Message Flow

The following shows the message stream from a single `query()` call, with token usage reported at each step and the authoritative total at the end:

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

# Final: Result message with authoritative total
result                %{total_cost_usd: 0.0042, usage: %{...}}
```

Each step produces one or more assistant messages. Each assistant message contains a nested message with an `id` and `usage` map with token counts (`input_tokens`, `output_tokens`). When Claude uses tools in parallel, multiple messages share the same `id` with identical usage data. Track which IDs you have already counted and skip duplicates to avoid inflated totals.

When the `query()` call completes, the SDK emits a `ClaudeCode.Message.ResultMessage` with `total_cost_usd` and cumulative `usage`. If you make multiple `query()` calls (for example, in a multi-turn session), each result only reflects the cost of that individual call. If you only need the total cost, you can ignore the per-step usage and read this single value.

## Get the Total Cost of a Query

The `ClaudeCode.Message.ResultMessage` is the last message in every `query()` call. It includes `total_cost_usd`, the cumulative cost across all steps in that call. This works for both success and error results. If you use sessions to make multiple `query()` calls, each result only reflects the cost of that individual call.

```elixir
result =
  session
  |> ClaudeCode.stream("Summarize this project")
  |> ClaudeCode.Stream.final_result()

result.total_cost_usd
# => 0.0042
```

## Track Per-Step Usage

Each assistant message contains a nested message with an `id` and `usage` map with token counts. When Claude uses tools in parallel, multiple messages share the same `id` with identical usage data. Track which IDs you have already counted and skip duplicates to avoid inflated totals.

> **Warning:** Parallel tool calls produce multiple assistant messages whose nested message shares the same `id` and identical usage. Always deduplicate by ID to get accurate per-step token counts.

```elixir
alias ClaudeCode.Message.AssistantMessage

# Accumulate input and output tokens, counting each unique message ID only once
session
|> ClaudeCode.stream("Analyze this codebase and run tests")
|> Enum.reduce(%{}, fn
  %AssistantMessage{message: %{id: id, usage: usage}}, seen ->
    Map.put_new(seen, id, usage)

  _, seen ->
    seen
end)
# Result: %{"msg_1" => %{output_tokens: 100, ...}, "msg_2" => %{output_tokens: 98, ...}}
```

## Per-Model Usage Breakdown

The `model_usage` field on `ClaudeCode.Message.ResultMessage` provides a map of model name to per-model token counts and cost. This is useful when you run multiple models (for example, Haiku for subagents and Opus for the main agent) and want to see where tokens are going.

```elixir
result =
  session
  |> ClaudeCode.stream("Complex task")
  |> ClaudeCode.Stream.final_result()

# model_usage is a map of model name to per-model usage data
result.model_usage
# => %{
#   "claude-sonnet-4-20250514" => %{
#     cost_usd: 0.003,
#     input_tokens: 1000,
#     output_tokens: 200,
#     cache_read_input_tokens: 500,
#     cache_creation_input_tokens: nil,
#     web_search_requests: 0,
#     context_window: 200_000,
#     max_output_tokens: 16_384
#   }
# }
```

## Accumulate Costs Across Multiple Calls

Each `query()` call returns its own `total_cost_usd`. The SDK does not provide a session-level total, so if your application makes multiple `query()` calls (for example, in a multi-turn session or across different users), accumulate the totals yourself.

```elixir
alias ClaudeCode.Message.ResultMessage

# Track cumulative cost across multiple query() calls
prompts = [
  "Read the files in lib/ and summarize the architecture",
  "List all public functions in lib/my_app/auth.ex"
]

total_spend =
  Enum.reduce(prompts, 0.0, fn prompt, acc ->
    %ResultMessage{total_cost_usd: cost} =
      session
      |> ClaudeCode.stream(prompt)
      |> ClaudeCode.Stream.final_result()

    acc + (cost || 0.0)
  end)

# total_spend now contains the combined cost of both calls
```

## Implementation: Cost Tracking System

Here is a complete example of implementing a cost tracking system using an OTP Agent:

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

CostTracker.summary()
# => %{steps: 3, step_usages: [...], total_cost: 0.0042}
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

## Handle Errors, Caching, and Token Discrepancies

For accurate cost tracking, account for failed conversations, cache token pricing, and occasional reporting inconsistencies.

### Resolve Output Token Discrepancies

In rare cases, you might observe different `output_tokens` values for messages with the same ID. When this occurs:

1. **Use the highest value:** the final message in a group typically contains the accurate total.
2. **Verify against total cost:** the `total_cost_usd` in the result message is authoritative.
3. **Report inconsistencies:** file issues at the [Claude Code GitHub repository](https://github.com/anthropics/claude-code/issues).

### Track Costs on Failed Conversations

Both success and error result messages include `usage` and `total_cost_usd`. If a conversation fails mid-way, you still consumed tokens up to the point of failure. Always read cost data from the result message regardless of its `subtype`.

### Track Cache Tokens

The Agent SDK automatically uses [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) to reduce costs on repeated content. You do not need to configure caching yourself. The usage map includes two additional fields for cache tracking:

- `cache_creation_input_tokens`: tokens used to create new cache entries (charged at a higher rate than standard input tokens).
- `cache_read_input_tokens`: tokens read from existing cache entries (charged at a reduced rate).

Track these separately from `input_tokens` to understand caching savings. These fields appear on the `usage` map of `ClaudeCode.Message.ResultMessage`.

## Best Practices

1. **Use Message IDs for Deduplication**: Always track processed message IDs to avoid double-charging
2. **Monitor the Result Message**: The final result contains authoritative cumulative usage (use `ClaudeCode.Stream.final_result/1`)
3. **Implement Logging**: Log all usage data for auditing and debugging
4. **Handle Failures Gracefully**: Track partial usage even if a conversation fails
5. **Consider Streaming**: For streaming responses, accumulate usage as messages arrive with `Stream.each/2`

## Usage Fields Reference

The `usage` map on `ClaudeCode.Message.ResultMessage` contains:

| Field                         | Description                                                          |
| ----------------------------- | -------------------------------------------------------------------- |
| `input_tokens`                | Base input tokens processed                                          |
| `output_tokens`               | Tokens generated in the response                                     |
| `cache_creation_input_tokens` | Tokens used to create cache entries                                  |
| `cache_read_input_tokens`     | Tokens read from cache                                               |
| `service_tier`                | The service tier used (for example, `"standard"`)                    |
| `server_tool_use`             | Map with `web_search_requests` and `web_fetch_requests` counts       |
| `cache_creation`              | Map with `ephemeral_5m_input_tokens` and `ephemeral_1h_input_tokens` |

The `total_cost_usd` field is a top-level field on `ClaudeCode.Message.ResultMessage` itself (not inside `usage`).

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

## Example: Building a Billing Dashboard

Here is how to aggregate usage data for a billing dashboard across multiple users:

```elixir
defmodule BillingAggregator do
  @moduledoc """
  Aggregates cost data across users for a billing dashboard.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def process_user_request(session, user_id, prompt) do
    {:ok, _} = CostTracker.start_link([])

    session
    |> ClaudeCode.stream(prompt)
    |> Stream.each(&CostTracker.process_message/1)
    |> Stream.run()

    summary = CostTracker.summary()

    total_tokens =
      Enum.reduce(summary.step_usages, 0, fn step, acc ->
        acc + (step.usage[:input_tokens] || 0) + (step.usage[:output_tokens] || 0)
      end)

    Agent.update(__MODULE__, fn state ->
      current = Map.get(state, user_id, %{total_tokens: 0, total_cost: 0.0, conversations: 0})

      Map.put(state, user_id, %{
        total_tokens: current.total_tokens + total_tokens,
        total_cost: current.total_cost + summary.total_cost,
        conversations: current.conversations + 1
      })
    end)
  end

  def get_user_billing(user_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state, user_id, %{total_tokens: 0, total_cost: 0.0, conversations: 0})
    end)
  end
end
```

## Related Documentation

- [Permissions](permissions.md) - Managing tool permissions
- [Stop Reasons](stop-reasons.md) - Understanding error subtypes
- [Hosting](hosting.md) - Production deployment
- [Secure Deployment](secure-deployment.md) - Budget and safety controls
