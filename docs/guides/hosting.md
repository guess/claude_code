# Hosting

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hosting). Examples are adapted for Elixir.

⚠️ TODO: THESE DOCS ARE INCOMPLETE

Deploy ClaudeCode sessions in production using OTP supervision trees and Elixir releases.

## Supervision Trees

Use `ClaudeCode.Supervisor` to manage multiple agent sessions with automatic restart:

```elixir
# In your Application module
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
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

### Supervisor Options

```elixir
{ClaudeCode.Supervisor, session_configs,
  name: MyApp.ClaudeSupervisor,
  max_restarts: 5,
  max_seconds: 10
}
```

### Dynamic Sessions

Add and remove sessions at runtime:

```elixir
# Start a new session under the supervisor
ClaudeCode.Supervisor.start_session(MyApp.ClaudeSupervisor, [
  name: :temp_agent,
  system_prompt: "Handle this specific task",
  max_turns: 5
])

# Check active sessions
ClaudeCode.Supervisor.count_sessions(MyApp.ClaudeSupervisor)
# => 4

# Remove when done
ClaudeCode.Supervisor.terminate_session(MyApp.ClaudeSupervisor, :temp_agent)
```

## Elixir Releases

For deploying with `mix release`, ensure the CLI binary is included:

```elixir
# mix.exs
defp deps do
  [{:claude_code, "~> 0.17"}]
end
```

In your release configuration:

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

For alternative setups, see the [CLI Configuration](../advanced/configuration.md#cli-configuration) docs.

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
    # Round-robin or least-busy selection
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

Monitor session health with Telemetry or periodic checks:

```elixir
defmodule MyApp.HealthCheck do
  use GenServer

  def init(_) do
    schedule_check()
    {:ok, %{}}
  end

  def handle_info(:check, state) do
    sessions = ClaudeCode.Supervisor.list_sessions(MyApp.ClaudeSupervisor)

    Enum.each(sessions, fn {name, pid, _, _} ->
      case ClaudeCode.health(pid) do
        :healthy -> :ok
        {:unhealthy, reason} ->
          Logger.warning("Session #{inspect(name)} unhealthy: #{inspect(reason)}")
      end
    end)

    schedule_check()
    {:noreply, state}
  end

  defp schedule_check, do: Process.send_after(self(), :check, 30_000)
end
```

## Next Steps

- [Secure Deployment](secure-deployment.md) - Security hardening
- [Sessions](sessions.md) - Session management details
- [Cost Tracking](cost-tracking.md) - Monitor API costs
