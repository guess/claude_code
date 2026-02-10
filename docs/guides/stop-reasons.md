# Handling Stop Reasons

Detect refusals and other stop reasons directly from result messages in the SDK.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/stop-reasons). Examples are adapted for Elixir.

The `stop_reason` field on `ClaudeCode.Message.ResultMessage` tells you why the model stopped generating. This is the recommended way to detect refusals, max-token limits, and other termination conditions (no stream parsing required).

> **Note:** `stop_reason` is available on every `ClaudeCode.Message.ResultMessage`, regardless of whether streaming is enabled. You don't need to set `include_partial_messages: true`.

## Reading stop_reason

The `stop_reason` field is present on both success and error result messages. Use `ClaudeCode.Stream.final_result/1` to extract the `ClaudeCode.Message.ResultMessage` from a stream:

```elixir
session
|> ClaudeCode.stream("Write a poem about the ocean")
|> ClaudeCode.Stream.final_result()
|> case do
  %{stop_reason: :refusal} ->
    IO.puts("The model declined this request.")

  result ->
    IO.puts("Stop reason: #{result.stop_reason}")
end
```

## Available stop reasons

| Stop reason      | Meaning                                                                                                                                           |
| :--------------- | :------------------------------------------------------------------------------------------------------------------------------------------------ |
| `:end_turn`      | The model finished generating its response normally.                                                                                              |
| `:max_tokens`    | The response reached the maximum output token limit.                                                                                              |
| `:stop_sequence` | The model generated a configured stop sequence.                                                                                                   |
| `:refusal`       | The model declined to fulfill the request.                                                                                                        |
| `:tool_use`      | The model's final output was a tool call. This is uncommon in SDK results because tool calls are normally executed before the result is returned. |
| `nil`            | No API response was received; for example, an error occurred before the first request, or the result was replayed from a cached session.          |

## Stop reasons on error results

Error results (such as `:error_max_turns` or `:error_during_execution`) also carry `stop_reason`. The value reflects the last assistant message received before the error occurred:

| Result subtype                         | `stop_reason` value                                                                |
| :------------------------------------- | :--------------------------------------------------------------------------------- |
| `:success`                             | The stop reason from the final assistant message.                                  |
| `:error_max_turns`                     | The stop reason from the last assistant message before the turn limit was hit.     |
| `:error_max_budget_usd`                | The stop reason from the last assistant message before the budget was exceeded.    |
| `:error_max_structured_output_retries` | The stop reason from the last assistant message before the retry limit was hit.    |
| `:error_during_execution`              | The last stop reason seen, or `nil` if the error occurred before any API response. |

```elixir
session
|> ClaudeCode.stream("Refactor this module", max_turns: 3)
|> ClaudeCode.Stream.final_result()
|> case do
  %{subtype: :error_max_turns} = result ->
    IO.puts("Hit turn limit. Last stop reason: #{result.stop_reason}")
    # stop_reason might be :end_turn or :tool_use
    # depending on what the model was doing when the limit hit

  _result ->
    :ok
end
```

## Detecting refusals

`stop_reason == :refusal` is the simplest way to detect when the model declines a request. Previously, detecting refusals required enabling partial message streaming and manually scanning stream events for `message_delta`. With `stop_reason` on the `ClaudeCode.Message.ResultMessage`, you can check directly:

```elixir
session
|> ClaudeCode.stream("Summarize this article")
|> ClaudeCode.Stream.final_result()
|> case do
  %{stop_reason: :refusal} ->
    IO.puts("Request was declined. Please revise your prompt.")

  %{subtype: :success, result: text} ->
    IO.puts(text)

  result ->
    IO.puts("Unexpected result: #{inspect(result.subtype)}")
end
```

## Next steps

- [Streaming Output](streaming-output.md) - Access raw API events including `message_delta` as they arrive
- [Structured Output](structured-outputs.md) - Get typed JSON responses from the agent
- [Cost Tracking](cost-tracking.md) - Understand token usage and billing from result messages
