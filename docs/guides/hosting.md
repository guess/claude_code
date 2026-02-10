# Hosting the Agent SDK

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hosting). Examples are adapted for Elixir.

Deploy ClaudeCode sessions in production using Elixir releases and OTP patterns.

## Session Patterns

Every ClaudeCode session is a GenServer wrapping a dedicated CLI subprocess. Each session maintains its own conversation context -- sessions cannot be shared across independent conversations. Choose the pattern that fits your use case:

### Per-request sessions

For stateless or one-off work, use `ClaudeCode.query/2`. It starts a session, runs the query, and stops the session automatically:

```elixir
{:ok, result} = ClaudeCode.query("Summarize this PR",
  allowed_tools: ["Read", "Grep"]
)
```

### Per-user sessions

For multi-turn conversations (e.g., a chat UI), start a session linked to the caller. When the LiveView or parent process dies, the session cleans up automatically:

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, session} = ClaudeCode.start_link(
      system_prompt: "You are a helpful assistant."
    )

    {:ok, assign(socket, claude: session)}
  end

  def handle_event("send", %{"message" => msg}, socket) do
    Task.start(fn ->
      socket.assigns.claude
      |> ClaudeCode.stream(msg, include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(&send(socket.root_pid, {:chunk, &1}))

      send(socket.root_pid, :stream_done)
    end)

    {:noreply, socket}
  end

  def handle_info({:chunk, chunk}, socket) do
    {:noreply, assign(socket, response: socket.assigns.response <> chunk)}
  end

  def handle_info(:stream_done, socket) do
    {:noreply, assign(socket, streaming: false)}
  end
end
```

### Per-request with isolation

For server-side processing where each request needs a fresh session:

```elixir
defmodule MyApp.Agent do
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

## Supervised Sessions

`ClaudeCode.Supervisor` manages named, long-lived sessions with automatic restart. This is useful for **dedicated single-purpose agents** like a CI bot or a background job processor -- cases where one caller owns the session at a time.

> **Caveat:** Each supervised session maintains conversation context across all queries. If multiple callers use the same named session concurrently, their queries serialize through the GenServer and share context, which fills the context window quickly with unrelated conversations. For multi-user workloads, prefer per-user or per-request sessions.

```elixir
# application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyAppWeb.Endpoint,
      {ClaudeCode.Supervisor, [
        [name: :ci_reviewer, system_prompt: "You review code for CI pipelines"]
      ]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end

# Use from a single-purpose caller (e.g., a CI webhook handler)
:ci_reviewer
|> ClaudeCode.stream("Review this diff: #{diff}")
|> ClaudeCode.Stream.final_text()
```

### Dynamic Sessions

Add and remove sessions at runtime:

```elixir
{:ok, supervisor} = ClaudeCode.Supervisor.start_link([])

# Add sessions on demand
ClaudeCode.Supervisor.start_session(supervisor, [
  name: :temp_session,
  system_prompt: "Temporary helper"
])

# Remove when done
ClaudeCode.Supervisor.terminate_session(supervisor, :temp_session)

# List active sessions
ClaudeCode.Supervisor.list_sessions(supervisor)
```

### Supervisor Options

```elixir
{ClaudeCode.Supervisor, session_configs,
  name: MyApp.ClaudeSupervisor,
  max_restarts: 5,
  max_seconds: 10
}
```

### Management API

```elixir
ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)
ClaudeCode.Supervisor.count_sessions(ClaudeCode.Supervisor)
ClaudeCode.Supervisor.restart_session(ClaudeCode.Supervisor, :ci_reviewer)
ClaudeCode.Supervisor.start_session(ClaudeCode.Supervisor, name: :temp, system_prompt: "Helper")
ClaudeCode.Supervisor.terminate_session(ClaudeCode.Supervisor, :temp)
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

Plan accordingly when running multiple concurrent sessions. For workloads with many users but low concurrency, consider stopping idle sessions and resuming on demand with `resume: session_id`.

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
    case ClaudeCode.query("ping", max_turns: 1, timeout: 10_000) do
      {:ok, _} -> :healthy
      {:error, reason} -> {:unhealthy, reason}
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
