# Structured Outputs

Return validated JSON from agent workflows using JSON Schema. Get type-safe, structured data after multi-turn tool use.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/structured-outputs). Examples are adapted for Elixir.

Structured outputs let you define the exact shape of data you want back from an agent. The agent can use any tools it needs to complete the task, and you still get validated JSON matching your schema at the end. Define a [JSON Schema](https://json-schema.org/understanding-json-schema/about) for the structure you need, and the SDK guarantees the output matches it.

## Why structured outputs?

Agents return free-form text by default, which works for chat but not when you need to use the output programmatically. Structured outputs give you typed data you can pass directly to your application logic, database, or UI components.

Consider a recipe app where an agent searches the web and brings back recipes. Without structured outputs, you get free-form text that you'd need to parse yourself. With structured outputs, you define the shape you want and get typed data you can use directly in your app.

**Without structured outputs:**

```text
Here's a classic chocolate chip cookie recipe!

**Chocolate Chip Cookies**
Prep time: 15 minutes | Cook time: 10 minutes

Ingredients:
- 2 1/4 cups all-purpose flour
- 1 cup butter, softened
...
```

To use this in your app, you'd need to parse out the title, convert "15 minutes" to a number, separate ingredients from instructions, and handle inconsistent formatting across responses.

**With structured outputs:**

```json
{
  "name": "Chocolate Chip Cookies",
  "prep_time_minutes": 15,
  "cook_time_minutes": 10,
  "ingredients": [
    { "item": "all-purpose flour", "amount": 2.25, "unit": "cups" },
    { "item": "butter, softened", "amount": 1, "unit": "cup" }
  ],
  "steps": ["Preheat oven to 375F", "Cream butter and sugar"]
}
```

Typed data you can use directly in your UI.

## Quick start

To use structured outputs, define a [JSON Schema](https://json-schema.org/understanding-json-schema/about) describing the shape of data you want, then pass it via the `output_format` option. When the agent finishes, the `ClaudeCode.Message.ResultMessage` struct includes a `structured_output` field with validated data matching your schema.

The example below asks the agent to research Anthropic and return the company name, year founded, and headquarters as structured output.

```elixir
# Define the shape of data you want back
schema = %{
  "type" => "object",
  "properties" => %{
    "company_name" => %{"type" => "string"},
    "founded_year" => %{"type" => "number"},
    "headquarters" => %{"type" => "string"}
  },
  "required" => ["company_name"]
}

{:ok, result} = ClaudeCode.query(
  "Research Anthropic and provide key company information",
  output_format: %{type: :json_schema, schema: schema}
)

# The result message contains structured_output with validated data
IO.inspect(result.structured_output)
# %{"company_name" => "Anthropic", "founded_year" => 2021, "headquarters" => "San Francisco, CA"}
```

## Defining schemas

The official SDKs support [Zod](https://zod.dev/) (TypeScript) and [Pydantic](https://docs.pydantic.dev/latest/) (Python) for type-safe schema definitions with full type inference and runtime validation. Since Elixir doesn't have a built-in schema-to-JSON-Schema library, you define JSON Schema as plain maps. For complex schemas, consider extracting reusable schema fragments into module attributes or helper functions.

The example below defines a schema for a feature implementation plan with a summary, list of steps (each with complexity level), and potential risks:

```elixir
# Define a complex schema with nested objects and enums
schema = %{
  "type" => "object",
  "properties" => %{
    "feature_name" => %{"type" => "string"},
    "summary" => %{"type" => "string"},
    "steps" => %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "step_number" => %{"type" => "number"},
          "description" => %{"type" => "string"},
          "estimated_complexity" => %{
            "type" => "string",
            "enum" => ["low", "medium", "high"]
          }
        },
        "required" => ["step_number", "description", "estimated_complexity"]
      }
    },
    "risks" => %{
      "type" => "array",
      "items" => %{"type" => "string"}
    }
  },
  "required" => ["feature_name", "summary", "steps", "risks"]
}

{:ok, result} = ClaudeCode.query(
  "Plan how to add dark mode support to a React app. Break it into implementation steps.",
  output_format: %{type: :json_schema, schema: schema}
)

plan = result.structured_output
IO.puts("Feature: #{plan["feature_name"]}")
IO.puts("Summary: #{plan["summary"]}")

Enum.each(plan["steps"], fn step ->
  IO.puts("#{step["step_number"]}. [#{step["estimated_complexity"]}] #{step["description"]}")
end)
```

For reusable schemas, extract them into module attributes:

```elixir
defmodule MyApp.Schemas do
  @step_schema %{
    "type" => "object",
    "properties" => %{
      "step_number" => %{"type" => "number"},
      "description" => %{"type" => "string"},
      "estimated_complexity" => %{
        "type" => "string",
        "enum" => ["low", "medium", "high"]
      }
    },
    "required" => ["step_number", "description", "estimated_complexity"]
  }

  def feature_plan do
    %{
      "type" => "object",
      "properties" => %{
        "feature_name" => %{"type" => "string"},
        "summary" => %{"type" => "string"},
        "steps" => %{"type" => "array", "items" => @step_schema},
        "risks" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["feature_name", "summary", "steps", "risks"]
    }
  end
end
```

## Output format configuration

The `output_format` option accepts a map with:

- `type`: Set to `:json_schema` for structured outputs
- `schema`: A [JSON Schema](https://json-schema.org/understanding-json-schema/about) map defining your output structure

The SDK supports standard JSON Schema features including all basic types (object, array, string, number, boolean, null), `enum`, `const`, `required`, nested objects, and `$ref` definitions. For the full list of supported features and limitations, see the [JSON Schema limitations](https://docs.anthropic.com/en/docs/build-with-claude/structured-outputs#json-schema-limitations) documentation.

## Example: TODO tracking agent

This example demonstrates how structured outputs work with multi-step tool use. The agent needs to find TODO comments in the codebase, then look up git blame information for each one. It autonomously decides which tools to use (Grep to search, Bash to run git commands) and combines the results into a single structured response.

The schema includes optional fields (`author` and `date`) since git blame information might not be available for all files. The agent fills in what it can find and omits the rest.

```elixir
# Define structure for TODO extraction
todo_schema = %{
  "type" => "object",
  "properties" => %{
    "todos" => %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "text" => %{"type" => "string"},
          "file" => %{"type" => "string"},
          "line" => %{"type" => "number"},
          "author" => %{"type" => "string"},
          "date" => %{"type" => "string"}
        },
        "required" => ["text", "file", "line"]
      }
    },
    "total_count" => %{"type" => "number"}
  },
  "required" => ["todos", "total_count"]
}

# Agent uses Grep to find TODOs, Bash to get git blame info
{:ok, result} = ClaudeCode.query(
  "Find all TODO comments in this codebase and identify who added them",
  output_format: %{type: :json_schema, schema: todo_schema}
)

data = result.structured_output
IO.puts("Found #{data["total_count"]} TODOs")

Enum.each(data["todos"], fn todo ->
  IO.puts("#{todo["file"]}:#{todo["line"]} - #{todo["text"]}")

  if todo["author"] do
    IO.puts("  Added by #{todo["author"]} on #{todo["date"]}")
  end
end)
```

## Error handling

Structured output generation can fail when the agent cannot produce valid JSON matching your schema. This typically happens when the schema is too complex for the task, the task itself is ambiguous, or the agent hits its retry limit trying to fix validation errors.

When an error occurs, the `ClaudeCode.Message.ResultMessage` has a `subtype` indicating what went wrong:

| Subtype                                | Meaning                                                     |
| -------------------------------------- | ----------------------------------------------------------- |
| `:success`                             | Output was generated and validated successfully             |
| `:error_max_structured_output_retries` | Agent couldn't produce valid output after multiple attempts |

The example below checks the `subtype` field to determine whether the output was generated successfully or if you need to handle a failure:

```elixir
alias ClaudeCode.Message.ResultMessage

case ClaudeCode.query(
  "Extract contact info from the document",
  output_format: %{type: :json_schema, schema: contact_schema}
) do
  {:ok, result} ->
    # Use the validated output
    IO.inspect(result.structured_output)

  {:error, %ResultMessage{subtype: :error_max_structured_output_retries}} ->
    # Handle the failure - retry with simpler prompt, fall back to unstructured, etc.
    Logger.error("Could not produce valid output")

  {:error, reason} ->
    Logger.error("Unexpected error: #{inspect(reason)}")
end
```

**Tips for avoiding errors:**

- **Keep schemas focused.** Deeply nested schemas with many required fields are harder to satisfy. Start simple and add complexity as needed.
- **Match schema to task.** If the task might not have all the information your schema requires, make those fields optional.
- **Use clear prompts.** Ambiguous prompts make it harder for the agent to know what output to produce.

## With streaming

For multi-turn sessions or when you need to process intermediate messages (tool use, thinking) alongside the structured result, use `ClaudeCode.stream/3`:

```elixir
{:ok, session} = ClaudeCode.start_link()

result =
  session
  |> ClaudeCode.stream(
    "Analyze this code",
    output_format: %{type: :json_schema, schema: schema}
  )
  |> ClaudeCode.Stream.final_result()

IO.inspect(result.structured_output)
```

## Related resources

- [JSON Schema documentation](https://json-schema.org/) - Learn JSON Schema syntax for defining complex schemas with nested objects, arrays, enums, and validation constraints
- [API Structured Outputs](https://docs.anthropic.com/en/docs/build-with-claude/structured-outputs) - Use structured outputs with the Claude API directly for single-turn requests without tool use
- [Custom Tools](custom-tools.md) - Give your agent custom tools to call during execution before returning structured output
