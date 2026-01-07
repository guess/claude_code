# Production Supervision Guide

Use `ClaudeCode.Supervisor` for production-ready AI applications with fault tolerance and automatic restarts.

## Why Supervision?

Elixir's OTP supervision provides:

- **Automatic restart** - Sessions restart on crashes
- **Fault isolation** - One session crash doesn't affect others
- **Zero downtime** - Hot code reloading preserves state
- **Global access** - Named sessions work from anywhere

## Quick Start

Add to your application's supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyAppWeb.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :general_assistant],
      [name: :code_reviewer, system_prompt: "You review code for bugs"]
    ]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Use from anywhere:

```elixir
# Controller
def chat(conn, %{"message" => message}) do
  response =
    :general_assistant
    |> ClaudeCode.stream(message)
    |> ClaudeCode.Stream.text_content()
    |> Enum.join()

  json(conn, %{response: response})
end

# GenServer
def handle_call({:review, code}, _from, state) do
  result =
    :code_reviewer
    |> ClaudeCode.stream("Review: #{code}")
    |> ClaudeCode.Stream.text_content()
    |> Enum.join()

  {:reply, {:ok, result}, state}
end

# Task
Task.async(fn ->
  :general_assistant
  |> ClaudeCode.stream("Analyze: #{data}")
  |> Stream.run()
end)
```

## Session Management

### Static Named Sessions

Best for long-lived assistants with specific roles:

```elixir
{ClaudeCode.Supervisor, [
  [name: :assistant],
  [name: :code_reviewer, system_prompt: "You review code"],
  [name: :test_writer, system_prompt: "You write ExUnit tests"],
  [name: {:global, :distributed_helper}]  # Works across nodes
]}
```

### Dynamic Sessions

Add and remove sessions at runtime:

```elixir
# Start with base sessions
{ClaudeCode.Supervisor, [
  [name: :shared_assistant]
]}

# Add user-specific session
def create_user_session(user_id) do
  ClaudeCode.Supervisor.start_session(ClaudeCode.Supervisor, [
    name: {:user, user_id},
    system_prompt: "You are helping user #{user_id}"
  ])
end

# Query user session
{:user, user_id} |> ClaudeCode.stream(message) |> Stream.run()

# Clean up
def cleanup_user_session(user_id) do
  ClaudeCode.Supervisor.terminate_session(ClaudeCode.Supervisor, {:user, user_id})
end
```

### Registry-Based Sessions

For advanced session discovery:

```elixir
children = [
  {Registry, keys: :unique, name: MyApp.SessionRegistry},
  {ClaudeCode.Supervisor, [
    [name: {:via, Registry, {MyApp.SessionRegistry, :primary}}]
  ]}
]

# Access via registry
session = {:via, Registry, {MyApp.SessionRegistry, :primary}}
session |> ClaudeCode.stream("Hello") |> Stream.run()
```

## Fault Tolerance

### Automatic Restart

Sessions restart transparently after crashes:

```elixir
:assistant |> ClaudeCode.stream("Complex task") |> Stream.run()
# Even if :assistant crashes, it restarts automatically
:assistant |> ClaudeCode.stream("Another task") |> Stream.run()
```

Note: Conversation history is lost on restart.

### Independent Failure

One session crash doesn't affect others:

```elixir
# If :code_reviewer crashes, :test_writer continues working
try do
  :code_reviewer |> ClaudeCode.stream(bad_input) |> Stream.run()
catch
  :error, _ -> :crashed
end

# Still works
tests =
  :test_writer
  |> ClaudeCode.stream("Write tests")
  |> ClaudeCode.Stream.text_content()
  |> Enum.join()
```

### Management API

```elixir
# List sessions
ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)

# Count sessions
ClaudeCode.Supervisor.count_sessions(ClaudeCode.Supervisor)

# Restart session (clears history)
ClaudeCode.Supervisor.restart_session(ClaudeCode.Supervisor, :assistant)

# Add session at runtime
ClaudeCode.Supervisor.start_session(ClaudeCode.Supervisor, [
  name: :temporary,
  system_prompt: "Temporary helper"
])

# Remove session
ClaudeCode.Supervisor.terminate_session(ClaudeCode.Supervisor, :temporary)
```

## Real-World Example

Web application with multiple AI assistants:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyAppWeb.Endpoint,
    {Registry, keys: :unique, name: MyApp.AIRegistry},
    {ClaudeCode.Supervisor, [
      [name: {:via, Registry, {MyApp.AIRegistry, :support}},
       system_prompt: "You provide customer support"],

      [name: {:via, Registry, {MyApp.AIRegistry, :dev}},
       system_prompt: "You help developers integrate our API"],

      [name: {:via, Registry, {MyApp.AIRegistry, :analytics}},
       system_prompt: "You analyze data and generate insights"]
    ]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# lib/my_app_web/controllers/support_controller.ex
def chat(conn, %{"message" => message}) do
  session = {:via, Registry, {MyApp.AIRegistry, :support}}

  try do
    response =
      session
      |> ClaudeCode.stream(message)
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()

    json(conn, %{response: response})
  catch
    _ -> conn |> put_status(500) |> json(%{error: "Unavailable"})
  end
end
```

## Health Checks

```elixir
defmodule MyApp.HealthCheck do
  def ai_status do
    sessions = ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)

    %{
      total: length(sessions),
      active: Enum.count(sessions, fn {_, pid, _, _} -> Process.alive?(pid) end)
    }
  end

  def test_connectivity do
    try do
      :assistant
      |> ClaudeCode.stream("ping", timeout: 10_000)
      |> Stream.run()

      :healthy
    catch
      error -> {:unhealthy, error}
    end
  end
end
```

## Configuration

### Per-Session Configuration

```elixir
{ClaudeCode.Supervisor, [
  # Fast for simple queries
  [name: :quick, timeout: 30_000, max_turns: 5],

  # Deep analysis
  [name: :analyzer, timeout: 600_000, max_turns: 50],

  # Code assistant with file access
  [name: :coder,
   allowed_tools: ["View", "Edit", "Bash(git:*)"],
   add_dir: ["/app/lib"]]
]}
```

## Troubleshooting

**Session not found:**
```elixir
# Check if session exists
ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)
```

**Session keeps crashing:**
```elixir
# Validate configuration
valid_config = [
  name: :test,
  api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
  timeout: 60_000
]
```

## Next Steps

- [Configuration Guide](configuration.md) - All configuration options
- [Phoenix Integration](../integration/phoenix.md) - Web application patterns
- [Troubleshooting](../reference/troubleshooting.md) - Common issues
