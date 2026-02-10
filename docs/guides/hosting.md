# Hosting the Agent SDK

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hosting). Examples are adapted for Elixir.

Deploy ClaudeCode sessions in production using OTP supervision trees and Elixir releases.

## Supervision Trees

Use `ClaudeCode.Supervisor` to manage multiple agent sessions with automatic restart and fault isolation:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyAppWeb.Endpoint,
      {ClaudeCode.Supervisor, [
        [name: :assistant, system_prompt: "General-purpose helper"],
        [name: :code_reviewer, system_prompt: "You review Elixir code for quality"],
        [name: :test_writer, system_prompt: "You write ExUnit tests"]
      ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Use named sessions from anywhere in your app:

```elixir
# Controller
def chat(conn, %{"message" => message}) do
  response =
    :assistant
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
```

### Supervisor Options

```elixir
{ClaudeCode.Supervisor, session_configs,
  name: MyApp.ClaudeSupervisor,
  max_restarts: 5,
  max_seconds: 10
}
```

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

## Dynamic Sessions

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

## Elixir Releases

For deploying with `mix release`, ensure the CLI binary is included:

```elixir
# config/runtime.exs
config :claude_code,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: System.get_env("CLAUDE_MODEL", "sonnet")
```

The default `cli_path: :bundled` mode uses the CLI binary in `priv/bin/`, which is automatically included in releases. Pre-install it during your release build:

```bash
mix claude_code.install
```

For alternative setups, see the CLI Configuration section of `ClaudeCode.Options`.

## Resource Considerations

Each ClaudeCode session runs a separate CLI subprocess:

| Resource         | Per Session               |
| ---------------- | ------------------------- |
| OS process       | 1 Node.js process         |
| Memory           | ~50-100 MB                |
| File descriptors | 3 (stdin, stdout, stderr) |
| Ports            | 1 Erlang port             |

Plan accordingly when running multiple concurrent sessions.

## Scaling Patterns

### Task Pool

For handling many concurrent requests with a fixed number of sessions:

```elixir
defmodule MyApp.AgentPool do
  def query(prompt) do
    session = select_session()

    session
    |> ClaudeCode.stream(prompt)
    |> ClaudeCode.Stream.final_text()
  end

  defp select_session do
    sessions = ClaudeCode.Supervisor.list_sessions(MyApp.ClaudeSupervisor)
    {_id, pid, _, _} = Enum.random(sessions)
    pid
  end
end
```

### Per-Request Sessions

For isolation between requests:

```elixir
defmodule MyApp.IsolatedAgent do
  def run(prompt, opts \\ []) do
    {:ok, session} = ClaudeCode.start_link(opts)

    try do
      session
      |> ClaudeCode.stream(prompt)
      |> ClaudeCode.Stream.collect()
    after
      ClaudeCode.stop(session)
    end
  end
end
```

## Health Monitoring

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

## Troubleshooting

**Session not found:**
```elixir
ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)
```

**Session keeps crashing:**
```elixir
valid_config = [
  name: :test,
  api_key: System.fetch_env!("ANTHROPIC_API_KEY"),
  timeout: 60_000
]
```

## Next Steps

- [Secure Deployment](secure-deployment.md) - Security hardening
- [Sessions](sessions.md) - Session management details
- [Cost Tracking](cost-tracking.md) - Monitor API costs
