# Stop Reasons

When Claude finishes responding, the `ResultMessage` contains information about why the conversation stopped and whether it succeeded.

## ResultMessage Structure

```elixir
%ClaudeCode.Message.ResultMessage{
  type: :result,
  subtype: :success,          # or an error subtype
  is_error: false,            # true if something went wrong
  result: "The answer is 42", # final response text (nil on error)
  stop_reason: :end_turn,     # why the API stopped generating
  duration_ms: 1234.5,        # total wall-clock time
  duration_api_ms: 987.2,     # time spent in API calls
  num_turns: 3,               # number of agentic turns taken
  total_cost_usd: 0.015,      # total cost of the conversation
  session_id: "abc-123",      # session ID for resuming
  usage: %{                   # aggregate token usage
    input_tokens: 500,
    output_tokens: 200,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 100
  },
  structured_output: nil,     # parsed JSON if output_format was set
  errors: nil                 # list of error strings on failure
}
```

## Pattern Matching on Results

### From `query/2`

```elixir
case ClaudeCode.query("Explain recursion") do
  {:ok, %{subtype: :success} = result} ->
    IO.puts(result.result)

  {:error, %{subtype: :error_max_turns}} ->
    IO.puts("Hit the turn limit")

  {:error, %{subtype: :error_during_execution, errors: errors}} ->
    IO.puts("Execution error: #{inspect(errors)}")

  {:error, reason} ->
    IO.puts("SDK error: #{inspect(reason)}")
end
```

### From a Stream

```elixir
session
|> ClaudeCode.stream("Complex task")
|> Enum.each(fn
  %ClaudeCode.Message.ResultMessage{is_error: false} = result ->
    IO.puts("Done: #{result.result}")

  %ClaudeCode.Message.ResultMessage{is_error: true} = result ->
    IO.puts("Error (#{result.subtype}): #{inspect(result.errors)}")

  _other ->
    :ok
end)
```

## Result Subtypes

| Subtype | `is_error` | Description |
|---------|-----------|-------------|
| `:success` | `false` | Normal completion. `result` contains the response. |
| `:error_max_turns` | `true` | Hit the `max_turns` limit. |
| `:error_during_execution` | `true` | An error occurred during tool execution or processing. |
| `:error_max_budget_usd` | `true` | Hit the `max_budget_usd` cost limit. |
| `:error_max_structured_output_retries` | `true` | Failed to produce valid structured output after retries. |

## Stop Reasons

The `stop_reason` field indicates why the Claude API stopped generating:

| Stop Reason | Description |
|------------|-------------|
| `:end_turn` | Claude finished its response naturally. |
| `:max_tokens` | Hit the maximum output token limit. |
| `:stop_sequence` | Hit a configured stop sequence. |
| `:tool_use` | Claude is requesting tool execution (intermediate, not final). |

## Checking Success

```elixir
result = session
|> ClaudeCode.stream("Do a task")
|> ClaudeCode.Stream.collect()

if result.is_error do
  Logger.error("Task failed: #{result.result}")
else
  Logger.info("Task completed in #{length(result.tool_calls)} tool calls")
end
```

## Next Steps

- [Permissions](permissions.md) - Control tool access and permission modes
- [Cost Tracking](cost-tracking.md) - Monitor usage and costs
