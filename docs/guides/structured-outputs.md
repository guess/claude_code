# Structured Outputs

Get Claude's responses as structured JSON instead of free-form text.

## Basic Usage

Use the `output_format` option with a JSON Schema:

```elixir
schema = %{
  "type" => "object",
  "properties" => %{
    "name" => %{"type" => "string"},
    "age" => %{"type" => "integer"},
    "hobbies" => %{
      "type" => "array",
      "items" => %{"type" => "string"}
    }
  },
  "required" => ["name", "age"]
}

{:ok, result} = ClaudeCode.query(
  "Generate a profile for a fictional character",
  output_format: %{type: :json_schema, schema: schema}
)

# The result text is valid JSON matching the schema
profile = Jason.decode!(result.result)
IO.inspect(profile)
# => %{"name" => "Elena Voss", "age" => 34, "hobbies" => ["rock climbing", "painting"]}
```

## With Sessions

```elixir
{:ok, session} = ClaudeCode.start_link()

schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "issues" => %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "severity" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
          "description" => %{"type" => "string"},
          "line" => %{"type" => "integer"}
        }
      }
    }
  }
}

result =
  session
  |> ClaudeCode.stream("Review lib/my_app/api.ex for issues",
       output_format: %{type: :json_schema, schema: schema})
  |> ClaudeCode.Stream.final_text()

review = Jason.decode!(result)
IO.puts("Summary: #{review["summary"]}")
IO.puts("Issues found: #{length(review["issues"])}")
```

## Parsing from ResultMessage

The `ResultMessage` struct includes a `structured_output` field that may contain the pre-parsed output:

```elixir
session
|> ClaudeCode.stream("Analyze this code",
     output_format: %{type: :json_schema, schema: schema})
|> Enum.each(fn
  %ClaudeCode.Message.ResultMessage{structured_output: output} when not is_nil(output) ->
    IO.inspect(output, label: "Structured output")

  %ClaudeCode.Message.ResultMessage{result: text} ->
    # Fallback: parse from result text
    case Jason.decode(text) do
      {:ok, parsed} -> IO.inspect(parsed, label: "Parsed from text")
      {:error, _} -> IO.puts("Raw: #{text}")
    end

  _ -> :ok
end)
```

## Error Handling

If Claude fails to produce valid output after retries, the result will have `subtype: :error_max_structured_output_retries`:

```elixir
case ClaudeCode.query("Generate data", output_format: %{type: :json_schema, schema: schema}) do
  {:ok, result} ->
    Jason.decode!(result.result)

  {:error, %{subtype: :error_max_structured_output_retries}} ->
    Logger.error("Failed to generate valid structured output")
    nil

  {:error, reason} ->
    Logger.error("Error: #{inspect(reason)}")
    nil
end
```

## Next Steps

- [Modifying System Prompts](modifying-system-prompts.md) - Guide output with system prompts
- [Stop Reasons](stop-reasons.md) - Understanding result subtypes
