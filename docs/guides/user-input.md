# User Input

Surface Claude's approval requests and clarifying questions to users, then return their decisions to the SDK.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/user-input). Examples are adapted for Elixir.

---

While working on a task, Claude sometimes needs to check in with users. It might need permission before deleting files, or need to ask which database to use for a new project. Your application needs to surface these requests to users so Claude can continue with their input.

Claude requests user input in two situations: when it needs **permission to use a tool** (like deleting files or running commands), and when it has **clarifying questions** (via the `AskUserQuestion` tool). Both trigger your `:can_use_tool` callback, which pauses execution until you return a response. This is different from normal conversation turns where Claude finishes and waits for your next message.

For clarifying questions, Claude generates the questions and options. Your role is to present them to users and return their selections. You cannot add your own questions to this flow; if you need to ask users something yourself, do that separately in your application logic.

This guide shows you how to detect each type of request and respond appropriately.

## Detect when Claude needs input

Pass a `:can_use_tool` callback in your session or query options. The callback fires whenever Claude needs user input, receiving the tool input map and tool use ID as arguments:

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: fn %{tool_name: name} = input, _tool_use_id ->
    # Prompt user and return :allow or {:deny, reason}
    :allow
  end
)
```

The callback fires in two cases:

1. **Tool needs approval**: Claude wants to use a tool that is not auto-approved by [permission rules](permissions.md) or modes. Check the `:tool_name` field for the tool (e.g., `"Bash"`, `"Write"`).
2. **Claude asks a question**: Claude calls the `AskUserQuestion` tool. Check if `tool_name == "AskUserQuestion"` to handle it differently. If you specify a `:tools` list, include `"AskUserQuestion"` for this to work. See [Handle clarifying questions](#handle-clarifying-questions) for details.

> **Note:** To automatically allow or deny tools without prompting users, use [hooks](hooks.md) instead. Hooks execute before `:can_use_tool` and can allow, deny, or modify requests based on your own logic. You can also use the [`PermissionRequest` hook](hooks.md#available-hooks) to send external notifications (Slack, email, push) when Claude is waiting for approval.

## Handle tool approval requests

Once you have passed a `:can_use_tool` callback, it fires when Claude wants to use a tool that is not auto-approved. Your callback receives two arguments:

| Argument | Description |
|----------|-------------|
| `input` (map) | A map containing `:tool_name`, `:input`, and other fields about the tool Claude wants to use |
| `tool_use_id` | Currently always `nil` for `:can_use_tool` callbacks (reserved for future use) |

The `:input` field within the map contains tool-specific parameters. Common examples:

| Tool | Input fields |
|------|--------------|
| `Bash` | `"command"`, `"description"`, `"timeout"` |
| `Write` | `"file_path"`, `"content"` |
| `Edit` | `"file_path"`, `"old_string"`, `"new_string"` |
| `Read` | `"file_path"`, `"offset"`, `"limit"` |

You can display this information to the user so they can decide whether to allow or reject the action, then return the appropriate response.

The following example asks Claude to create and delete a test file. When Claude attempts each operation, the callback prints the tool request to the terminal and prompts for y/n approval:

```elixir
{:ok, session} = ClaudeCode.start_link(
  can_use_tool: fn %{tool_name: name, input: input}, _tool_use_id ->
    IO.puts("\nTool: #{name}")

    if name == "Bash" do
      IO.puts("Command: #{input["command"]}")
      if input["description"], do: IO.puts("Description: #{input["description"]}")
    else
      IO.puts("Input: #{inspect(input)}")
    end

    case IO.gets("Allow this action? (y/n): ") |> String.trim() do
      "y" -> {:allow, input}
      _ -> {:deny, "User denied this action"}
    end
  end
)

session
|> ClaudeCode.stream("Create a test file in /tmp and then delete it")
|> ClaudeCode.Stream.final_text()
|> IO.puts()
```

This example uses a y/n flow where any input other than "y" is treated as a denial. In practice, you might build a richer UI that lets users modify the request, provide feedback, or redirect Claude entirely. See [Respond to tool requests](#respond-to-tool-requests) for all the ways you can respond.

### Respond to tool requests

Your callback returns one of the following response types:

| Return | Effect |
|--------|--------|
| `:allow` | Permit the tool call |
| `{:allow, updated_input}` | Permit with modified input |
| `{:allow, updated_input, permissions: updates}` | Permit with modified input and permission updates |
| `{:deny, reason}` | Block the tool call with an explanation |
| `{:deny, reason, interrupt: true}` | Block and interrupt the session |

When allowing with input, pass the tool input (original or modified). When denying, provide a message explaining why. Claude sees this message and may adjust its approach.

```elixir
# Allow the tool to execute
:allow

# Allow with original input
{:allow, input}

# Block the tool
{:deny, "User rejected this action"}
```

Beyond allowing or denying, you can modify the tool's input or provide context that helps Claude adjust its approach:

- **Approve**: let the tool execute as Claude requested
- **Approve with changes**: modify the input before execution (e.g., sanitize paths, add constraints)
- **Reject**: block the tool and tell Claude why
- **Suggest alternative**: block but guide Claude toward what the user wants instead
- **Redirect entirely**: use [streaming input](streaming-vs-single-mode.md) to send Claude a completely new instruction

#### Approve

The user approves the action as-is. Return `:allow` and the tool executes exactly as Claude requested:

```elixir
can_use_tool: fn %{tool_name: name}, _id ->
  IO.puts("Claude wants to use #{name}")
  if confirm?("Allow this action?"), do: :allow, else: {:deny, "User declined"}
end
```

#### Approve with changes

The user approves but wants to modify the request first. You can change the input before the tool executes. Claude sees the result but is not told you changed anything. Useful for sanitizing parameters, adding constraints, or scoping access:

```elixir
can_use_tool: fn %{tool_name: "Bash", input: input}, _id ->
  # Scope all commands to sandbox
  sandboxed = Map.update!(input, "command", &String.replace(&1, "/tmp", "/tmp/sandbox"))
  {:allow, sandboxed}

%{input: input}, _id ->
  {:allow, input}
end
```

#### Reject

The user does not want this action to happen. Block the tool and provide a message explaining why. Claude sees this message and may try a different approach:

```elixir
can_use_tool: fn %{tool_name: name} = input, _id ->
  if confirm?("Allow #{name}?") do
    {:allow, input.input}
  else
    {:deny, "User rejected this action"}
  end
end
```

#### Suggest alternative

The user does not want this specific action, but has a different idea. Block the tool and include guidance in your message. Claude will read this and decide how to proceed based on your feedback:

```elixir
can_use_tool: fn %{tool_name: "Bash", input: %{"command" => cmd}} = _input, _id when cmd =~ "rm" ->
  {:deny, "User doesn't want to delete files. They asked if you could compress them into an archive instead."}

%{input: input}, _id ->
  {:allow, input}
end
```

#### Redirect entirely

For a complete change of direction (not just a nudge), use [streaming input](streaming-vs-single-mode.md) to send Claude a new instruction directly. This bypasses the current tool request and gives Claude entirely new instructions to follow.

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

## Handle clarifying questions

When Claude needs more direction on a task with multiple valid approaches, it calls the `AskUserQuestion` tool. This triggers your `:can_use_tool` callback with `tool_name` set to `"AskUserQuestion"`. The input contains Claude's questions as multiple-choice options, which you display to the user and return their selections.

> **Tip:** Clarifying questions are especially common in [plan mode](permissions.md#plan-mode-plan), where Claude explores the codebase and asks questions before proposing a plan. This makes plan mode ideal for interactive workflows where you want Claude to gather requirements before making changes.

### Step 1: Pass a `:can_use_tool` callback

Pass a `:can_use_tool` callback in your session or query options. By default, `AskUserQuestion` is available. If you specify a `:tools` list to restrict Claude's capabilities (for example, a read-only agent with only `Read`, `Glob`, and `Grep`), include `"AskUserQuestion"` in that list. Otherwise, Claude will not be able to ask clarifying questions:

```elixir
{:ok, session} = ClaudeCode.start_link(
  tools: ["Read", "Glob", "Grep", "AskUserQuestion"],
  can_use_tool: &my_tool_handler/2
)
```

### Step 2: Detect AskUserQuestion

In your callback, check if the tool name equals `"AskUserQuestion"` to handle it differently from other tools:

```elixir
def my_tool_handler(%{tool_name: "AskUserQuestion"} = input, tool_use_id) do
  handle_clarifying_questions(input)
end

def my_tool_handler(input, _tool_use_id) do
  prompt_for_approval(input)
end
```

### Step 3: Parse the question input

The input contains Claude's questions in a `"questions"` list. Each question has a `"question"` (the text to display), `"options"` (the choices), and `"multiSelect"` (whether multiple selections are allowed):

```json
{
  "questions": [
    {
      "question": "How should I format the output?",
      "header": "Format",
      "options": [
        { "label": "Summary", "description": "Brief overview" },
        { "label": "Detailed", "description": "Full explanation" }
      ],
      "multiSelect": false
    },
    {
      "question": "Which sections should I include?",
      "header": "Sections",
      "options": [
        { "label": "Introduction", "description": "Opening context" },
        { "label": "Conclusion", "description": "Final summary" }
      ],
      "multiSelect": true
    }
  ]
}
```

### Step 4: Collect answers from the user

Present the questions to the user and collect their selections. How you do this depends on your application: a terminal prompt, a LiveView form, a mobile dialog, etc.

### Step 5: Return answers to Claude

Build the `"answers"` map where each key is the `"question"` text and each value is the selected option's `"label"`:

| From the question object | Use as |
|--------------------------|--------|
| `"question"` field (e.g., `"How should I format the output?"`) | Key |
| Selected option's `"label"` field (e.g., `"Summary"`) | Value |

For multi-select questions, join multiple labels with `", "`. If you [support free-text input](#support-free-text-input), use the user's custom text as the value.

```elixir
{:allow, %{
  "questions" => input.input["questions"],
  "answers" => %{
    "How should I format the output?" => "Summary",
    "Which sections should I include?" => "Introduction, Conclusion"
  }
}}
```

### Question format

The input contains Claude's generated questions in a `"questions"` list. Each question has these fields:

| Field | Description |
|-------|-------------|
| `"question"` | The full question text to display |
| `"header"` | Short label for the question (max 12 characters) |
| `"options"` | List of 2-4 choices, each with `"label"` and `"description"` |
| `"multiSelect"` | If `true`, users can select multiple options |

Here is an example of the structure you will receive:

```json
{
  "questions": [
    {
      "question": "How should I format the output?",
      "header": "Format",
      "options": [
        { "label": "Summary", "description": "Brief overview of key points" },
        { "label": "Detailed", "description": "Full explanation with examples" }
      ],
      "multiSelect": false
    }
  ]
}
```

### Response format

Return an `"answers"` map that maps each question's `"question"` field to the selected option's `"label"`:

| Field | Description |
|-------|-------------|
| `"questions"` | Pass through the original questions list (required for tool processing) |
| `"answers"` | Map where keys are question text and values are selected labels |

For multi-select questions, join multiple labels with `", "`. For free-text input, use the user's custom text directly.

```json
{
  "questions": [...],
  "answers": {
    "How should I format the output?": "Summary",
    "Which sections should I include?": "Introduction, Conclusion"
  }
}
```

#### Support free-text input

Claude's predefined options will not always cover what users want. To let users type their own answer:

- Display an additional "Other" choice after Claude's options that accepts text input
- Use the user's custom text as the answer value (not the word "Other")

See the [complete example](#complete-example) below for a full implementation.

### Complete example

Claude asks clarifying questions when it needs user input to proceed. For example, when asked to help decide on a tech stack for a mobile app, Claude might ask about cross-platform vs native, backend preferences, or target platforms. These questions help Claude make decisions that match the user's preferences rather than guessing.

This example handles those questions in a terminal application:

1. **Route the request**: The `:can_use_tool` callback checks if the tool name is `"AskUserQuestion"` and routes to a dedicated handler
2. **Display questions**: The handler loops through the `"questions"` list and prints each question with numbered options
3. **Collect input**: The user can enter a number to select an option, or type free text directly (e.g., "jquery", "i don't know")
4. **Map answers**: The code checks if input is numeric (uses the option's label) or free text (uses the text directly)
5. **Return to Claude**: The response includes both the original `"questions"` list and the `"answers"` mapping

```elixir
defmodule MyApp.UserInput do
  @behaviour ClaudeCode.Hook

  @impl true
  def call(%{tool_name: "AskUserQuestion", input: input}, _tool_use_id) do
    handle_questions(input)
  end

  def call(%{input: input}, _tool_use_id) do
    # Auto-approve other tools for this example
    {:allow, input}
  end

  defp handle_questions(input) do
    questions = input["questions"] || []

    answers =
      Map.new(questions, fn q ->
        IO.puts("\n#{q["header"]}: #{q["question"]}")

        options = q["options"] || []

        Enum.with_index(options, 1)
        |> Enum.each(fn {opt, i} ->
          IO.puts("  #{i}. #{opt["label"]} - #{opt["description"]}")
        end)

        if q["multiSelect"] do
          IO.puts("  (Enter numbers separated by commas, or type your own answer)")
        else
          IO.puts("  (Enter a number, or type your own answer)")
        end

        response = IO.gets("Your choice: ") |> String.trim()
        {q["question"], parse_response(response, options)}
      end)

    {:allow, %{"questions" => questions, "answers" => answers}}
  end

  defp parse_response(response, options) do
    indices =
      response
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&Integer.parse/1)
      |> Enum.filter(&match?({_, ""}, &1))
      |> Enum.map(fn {n, _} -> n - 1 end)
      |> Enum.filter(&(&1 >= 0 and &1 < length(options)))

    case indices do
      [] -> response
      _ -> indices |> Enum.map(&Enum.at(options, &1)["label"]) |> Enum.join(", ")
    end
  end
end

{:ok, session} = ClaudeCode.start_link(can_use_tool: MyApp.UserInput)

session
|> ClaudeCode.stream("Help me decide on the tech stack for a new mobile app")
|> ClaudeCode.Stream.final_text()
|> IO.puts()
```

## Limitations

- **Subagents**: `AskUserQuestion` is not currently available in subagents spawned via the Task tool
- **Question limits**: each `AskUserQuestion` call supports 1-4 questions with 2-4 options each

## Other ways to get user input

The `:can_use_tool` callback and `AskUserQuestion` tool cover most approval and clarification scenarios, but the SDK offers other ways to get input from users:

### Streaming input

Use [streaming input](streaming-vs-single-mode.md) when you need to:

- **Interrupt the agent mid-task**: send a cancel signal or change direction while Claude is working
- **Provide additional context**: add information Claude needs without waiting for it to ask
- **Build chat interfaces**: let users send follow-up messages during long-running operations

Streaming input is ideal for conversational UIs where users interact with the agent throughout execution, not just at approval checkpoints.

### Custom tools

Use [custom tools](custom-tools.md) when you need to:

- **Collect structured input**: build forms, wizards, or multi-step workflows that go beyond `AskUserQuestion`'s multiple-choice format
- **Integrate external approval systems**: connect to existing ticketing, workflow, or approval platforms
- **Implement domain-specific interactions**: create tools tailored to your application's needs, like code review interfaces or deployment checklists

Custom tools give you full control over the interaction, but require more implementation work than using the built-in `:can_use_tool` callback.

## Related resources

- [Configure permissions](permissions.md) -- Set up permission modes and rules
- [Control execution with hooks](hooks.md) -- Run custom code at key points in the agent lifecycle
- [Sessions](sessions.md) -- Multi-turn conversations and session management
