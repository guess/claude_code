# ClaudeCode

An idiomatic Elixir SDK for Claude Code that leverages OTP patterns, functional composition, and the Actor model to provide a robust, fault-tolerant interface for AI-powered coding assistance.

## Features

- 🎭 **GenServer-based Sessions** - Each session is a supervised process with automatic recovery
- 🌊 **Native Streaming** - Built on Elixir's Stream module for efficient, lazy evaluation
- ⚙️ **Flattened Configuration** - Clean, intuitive options API with NimbleOptions validation
- 📊 **Option Precedence** - Query > Session > App Config > Defaults hierarchy
- 🛡️ **Behaviour-based Permissions** - Extensible permission system using Elixir behaviours
- 📊 **Telemetry Integration** - First-class observability with :telemetry
- 🔄 **Async & Sync APIs** - Choose between async streaming or synchronous responses
- ⚡ **LiveView Ready** - Designed for real-time Phoenix applications
- 🎯 **Pattern Matching** - Leverage Elixir's pattern matching for elegant message handling
- 🔧 **Tool Composition** - Compose complex workflows with pipe operators

## Installation

```elixir
def deps do
  [
    {:claude_code, "~> 0.4.0"}
  ]
end
```

## Quick Start

```elixir
# Start a session
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Query Claude (streaming)
session
|> ClaudeCode.query_stream("Write a GenServer for a rate limiter")
|> Stream.each(&IO.inspect/1)
|> Stream.run()

# Query Claude (synchronous)
{:ok, messages} = ClaudeCode.query(session, "Explain this code")
```

## Core API

### Session Management

ClaudeCode sessions are GenServers that maintain conversation state and handle all Claude interactions.

```elixir
# Start a session with flattened options
{:ok, session} = ClaudeCode.start_link(
  api_key: "sk-ant-...",
  model: "opus",
  system_prompt: "You are an expert Elixir developer",
  allowed_tools: ["View", "Edit", "Bash(git:*)"],
  cwd: "/path/to/project",
  max_turns: 20,
  timeout: 120_000
)

# Named sessions for global access
{:ok, _} = ClaudeCode.start_link(
  api_key: api_key,
  system_prompt: "You are helpful",
  name: {:global, :coding_assistant}
)

# Use application config defaults
# config/config.exs
config :claude_code,
  model: "opus",
  system_prompt: "You are an expert Elixir developer",

{:ok, session} = ClaudeCode.start_link(api_key: api_key)
# Automatically uses config defaults ↑
```

### Querying Claude

The primary interface mirrors the Python SDK's async pattern while feeling natural in Elixir:

```elixir
# Streaming query (returns a Stream)
stream = ClaudeCode.query_stream(session, "Create a Phoenix LiveView component")

# Process the stream
stream
|> Stream.filter(&match?(%ClaudeCode.AssistantMessage{}, &1))
|> Stream.flat_map(& &1.content)
|> Stream.filter(&match?(%ClaudeCode.TextBlock{}, &1))
|> Stream.map(& &1.text)
|> Enum.join()

# Synchronous query with option overrides (blocks until complete)
{:ok, messages} = ClaudeCode.query(session,
  "Fix the compilation errors",
  allowed_tools: ["View", "Edit"],
  timeout: :timer.minutes(5),
  system_prompt: "Focus on fixing syntax errors"
)
```

### Message Types

Pattern match on different message types for precise control:

```elixir
stream
|> Stream.each(fn
  %ClaudeCode.AssistantMessage{content: blocks} ->
    handle_assistant_blocks(blocks)

  %ClaudeCode.UserMessage{content: content} ->
    Logger.debug("User: #{content}")

  %ClaudeCode.ToolUseMessage{tool: tool, args: args} ->
    Logger.info("Claude is using #{tool}")

  %ClaudeCode.ResultMessage{result: result, error: nil} ->
    handle_tool_result(result)

  %ClaudeCode.ResultMessage{error: error} ->
    handle_tool_error(error)
end)
|> Stream.run()
```

### Content Blocks

```elixir
defp handle_assistant_blocks(blocks) do
  Enum.each(blocks, fn
    %ClaudeCode.TextBlock{text: text} ->
      IO.write(text)

    %ClaudeCode.ToolUseBlock{id: id, name: name, input: input} ->
      Logger.info("Tool use: #{name} with #{inspect(input)}")

    %ClaudeCode.ToolResultBlock{tool_use_id: id, output: output} ->
      Logger.debug("Tool result for #{id}: #{output}")
  end)
end
```

### Permission Handling

Define custom permission handlers using Elixir behaviours:

```elixir
defmodule MyApp.PermissionHandler do
  @behaviour ClaudeCode.PermissionHandler

  @impl true
  def handle_permission(:write, %{path: path}, _context) do
    cond do
      String.contains?(path, ".env") ->
        {:deny, "Cannot modify environment files"}

      String.starts_with?(path, "/tmp") ->
        :allow

      true ->
        {:confirm, "Allow writing to #{path}?"}
    end
  end

  @impl true
  def handle_permission(:bash, %{command: command}, _context) do
    if safe_command?(command) do
      :allow
    else
      {:confirm, "Execute command: #{command}?"}
    end
  end

  @impl true
  def handle_permission(_, _, _), do: :allow

  defp safe_command?(cmd) do
    safe_commands = ~w[ls pwd echo date whoami]
    first_word = cmd |> String.split() |> List.first()
    first_word in safe_commands
  end
end

# Use the custom handler
{:ok, session} = ClaudeCode.start_link(
  api_key: api_key,
  permission_handler: MyApp.PermissionHandler
)
```

### Permission Modes

Built-in permission modes for common scenarios:

```elixir
# Auto-accept read operations
%ClaudeCode.Options{
}

# Auto-accept file edits
%ClaudeCode.Options{
}

# Ask for confirmation on all tools
%ClaudeCode.Options{
}

# Custom combination
%ClaudeCode.Options{
    auto_accept: [:read],
    auto_deny: [:delete],
    confirm: [:write, :bash]
  }
}
```

### Error Handling

Comprehensive error types for different failure scenarios:

```elixir
case ClaudeCode.query(session, prompt) do
  {:ok, messages} ->
    process_messages(messages)

  {:error, %ClaudeCode.CLINotFoundError{}} ->
    Logger.error("Claude Code CLI not found. Please install it.")

  {:error, %ClaudeCode.CLIConnectionError{message: msg}} ->
    Logger.error("Connection failed: #{msg}")

  {:error, %ClaudeCode.ProcessError{exit_code: code}} ->
    Logger.error("Process exited with code: #{code}")

  {:error, %ClaudeCode.RateLimitError{retry_after: seconds}} ->
    Process.sleep(seconds * 1000)
    # Retry...

  {:error, error} ->
    Logger.error("Unexpected error: #{inspect(error)}")
end
```

### Telemetry Events

Monitor performance and usage:

```elixir
# Emitted events:
# [:claude_code, :query, :start]
# [:claude_code, :query, :stop]
# [:claude_code, :query, :exception]
# [:claude_code, :tool, :start]
# [:claude_code, :tool, :stop]
# [:claude_code, :message, :received]

:telemetry.attach(
  "log-queries",
  [:claude_code, :query, :stop],
  fn _event, measurements, metadata, _config ->
    Logger.info("""
    Query completed:
      Duration: #{measurements.duration / 1_000_000}ms
      Token count: #{metadata.token_count}
      Message count: #{metadata.message_count}
    """)
  end,
  nil
)
```

### Supervision

Build fault-tolerant applications with OTP supervision:

```elixir
defmodule MyApp.ClaudeSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Primary coding assistant
      {ClaudeCode,
        api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
        name: :main_assistant,
        system_prompt: "You are an expert Elixir developer",
        allowed_tools: ["View", "Edit"],
      },

      # Specialized test writer
      {ClaudeCode,
        api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
        name: :test_assistant,
        system_prompt: "You are an expert at writing ExUnit tests",
        allowed_tools: ["View", "Edit"],
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

### Phoenix LiveView Integration

Build real-time coding assistants:

```elixir
defmodule MyAppWeb.CodingAssistantLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, claude} = ClaudeCode.start_link(
      api_key: System.get_env("ANTHROPIC_API_KEY")
    )

    {:ok,
     socket
     |> assign(claude_session: claude)
     |> assign(messages: [])
     |> assign(streaming: false)}
  end

  @impl true
  def handle_event("submit", %{"prompt" => prompt}, socket) do
    # Start streaming in a separate process
    parent = self()

    Task.start(fn ->
      socket.assigns.claude_session
      |> ClaudeCode.query_stream(prompt)
      |> Stream.each(fn message ->
        send(parent, {:claude_message, message})
      end)
      |> Stream.run()

      send(parent, :claude_done)
    end)

    {:noreply, assign(socket, streaming: true)}
  end

  @impl true
  def handle_info({:claude_message, message}, socket) do
    {:noreply, update(socket, :messages, &[&1 | message])}
  end

  @impl true
  def handle_info(:claude_done, socket) do
    {:noreply, assign(socket, streaming: false)}
  end
end
```

### Advanced Patterns

#### Pipeline Composition

```elixir
defmodule MyApp.RefactorPipeline do
  import ClaudeCode.Pipeline

  def refactor_module(session, file_path) do
    session
    |> read_file(file_path)
    |> analyze("Identify code smells and improvements")
    |> refactor("Apply Elixir best practices")
    |> format_code()
    |> write_file(file_path)
    |> run_tests()
  end

  defp analyze(session, file_content, prompt) do
    session
    |> ClaudeCode.query("File content:\n#{file_content}\n\n#{prompt}")
    |> extract_analysis()
  end

  defp refactor(session, analysis, instructions) do
    prompt = """
    Based on this analysis:
    #{analysis}

    #{instructions}
    """

    session
    |> ClaudeCode.query(prompt)
    |> extract_code()
  end
end
```

#### Conversation Management

```elixir
defmodule MyApp.Conversation do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def add_context(conversation, context) do
    GenServer.call(conversation, {:add_context, context})
  end

  def ask(conversation, question) do
    GenServer.call(conversation, {:ask, question}, :infinity)
  end

  @impl true
  def init(opts) do
    {:ok, claude} = ClaudeCode.start_link(opts)
    {:ok, %{claude: claude, context: []}}
  end

  @impl true
  def handle_call({:ask, question}, from, state) do
    # Include context in the question
    full_prompt = build_prompt_with_context(question, state.context)

    # Stream response back to caller
    Task.start(fn ->
      response =
        state.claude
        |> ClaudeCode.query_stream(full_prompt)
        |> Enum.to_list()

      GenServer.reply(from, {:ok, response})
    end)

    {:noreply, state}
  end
end
```

#### Testing Support

```elixir
defmodule MyApp.ClaudeTest do
  use ExUnit.Case
  import ClaudeCode.Test

  test "generates valid Elixir code" do
    # Mock session with predefined responses
    session = mock_session([
      %ClaudeCode.AssistantMessage{
        content: [
          %ClaudeCode.TextBlock{
            text: "defmodule Example do\n  def hello, do: :world\nend"
          }
        ]
      }
    ])

    {:ok, messages} = ClaudeCode.query(session, "Generate example module")

    assert [%{content: [%{text: code}]}] = messages
    assert {:ok, _} = Code.string_to_quoted(code)
  end

  test "respects permission handler" do
    session = mock_session([],
      permission_handler: fn
        :write, %{path: "/etc/passwd"}, _ -> {:deny, "Nope!"}
        _, _, _ -> :allow
      end
    )

    assert {:error, %{reason: "Nope!"}} =
      ClaudeCode.query(session, "Write to /etc/passwd")
  end
end
```

## Configuration

```elixir
# config/config.exs
config :claude_code,
  # Global defaults
  model: "claude-3-5-sonnet-20241022",
  timeout: :timer.minutes(5),

  # Telemetry
  telemetry_prefix: [:my_app, :claude],

  # Connection pooling (for high-concurrency apps)
  pool_size: System.schedulers_online() * 2,
  pool_overflow: 10,

  # Retry configuration
  retry_attempts: 3,
  retry_delay: 1000,
  retry_max_delay: 10_000,

  # Global tool restrictions
  forbidden_tools: [:delete_file],

  # Enable debug logging
  debug: Mix.env() == :dev
```

## Best Practices

1. **Always supervise Claude sessions** - Use OTP supervision for fault tolerance
2. **Set appropriate timeouts** - Some operations may take time
3. **Handle streaming incrementally** - Don't collect entire streams in memory
4. **Use permission handlers** - Never trust AI with unrestricted file access
5. **Monitor with telemetry** - Track usage, performance, and costs
6. **Test with mocks** - Use `ClaudeCode.Test` for deterministic tests

## License

MIT License
