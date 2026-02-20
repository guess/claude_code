# Hosting

Deploy and host Claude Agent SDK in production environments.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/hosting). Examples are adapted for Elixir.

The Claude Agent SDK differs from traditional stateless LLM APIs in that it maintains conversational state and executes commands in a persistent environment. This guide covers the architecture, hosting considerations, and best practices for deploying SDK-based agents in production.

> For security hardening beyond basic sandboxing -- including network controls, credential management, and isolation options -- see [Secure Deployment](secure-deployment.md).

## Hosting Requirements

### Container-Based Sandboxing

For security and isolation, the SDK should run inside a sandboxed container environment. This provides process isolation, resource limits, network control, and ephemeral filesystems.

The SDK also supports programmatic sandbox configuration via the `:sandbox` option in `ClaudeCode.Options`.

### System Requirements

Each SDK instance requires:

- **Runtime dependencies**
  - Elixir 1.15+ / OTP 26+
  - Node.js (required by the Claude Code CLI)
  - Claude Code CLI -- either bundled via `mix claude_code.install` or globally installed with `npm install -g @anthropic-ai/claude-code`

- **Resource allocation**
  - Recommended: 1 GiB RAM, 5 GiB of disk, and 1 CPU (vary this based on your task as needed)

- **Network access**
  - Outbound HTTPS to `api.anthropic.com`
  - Optional: Access to MCP servers or external tools

## Understanding the SDK Architecture

Unlike stateless API calls, the Claude Agent SDK operates as a **long-running process** that:
- **Executes commands** in a persistent shell environment
- **Manages file operations** within a working directory
- **Handles tool execution** with context from previous interactions

In the Elixir SDK, each `ClaudeCode.Session` is a GenServer wrapping a dedicated CLI subprocess. Each session maintains its own conversation context -- sessions cannot be shared across independent conversations.

## Sandbox Provider Options

Several providers specialize in secure container environments for AI code execution:

- **[Modal Sandbox](https://modal.com/docs/guide/sandbox)** - [demo implementation](https://modal.com/docs/examples/claude-slack-gif-creator)
- **[Cloudflare Sandboxes](https://github.com/cloudflare/sandbox-sdk)**
- **[Daytona](https://www.daytona.io/)**
- **[E2B](https://e2b.dev/)**
- **[Fly Machines](https://fly.io/docs/machines/)**
- **[Vercel Sandbox](https://vercel.com/docs/functions/sandbox)**

For self-hosted options (Docker, gVisor, Firecracker) and detailed isolation configuration, see [Isolation Technologies](secure-deployment.md#isolation-technologies).

## Production Deployment Patterns

### Pattern 1: Ephemeral Sessions

Create a new container for each user task, then destroy it when complete.

Best for one-off tasks. The user may still interact with the AI while the task is completing, but once completed the container is destroyed.

**Examples:**
- **Bug Investigation & Fix:** Debug and resolve a specific issue with relevant context
- **Invoice Processing:** Extract and structure data from receipts/invoices for accounting systems
- **Translation Tasks:** Translate documents or content batches between languages
- **Image/Video Processing:** Apply transformations, optimizations, or extract metadata from media files

In Elixir, use `ClaudeCode.query/2` for stateless one-off work. It starts a session, runs the query, and stops the session automatically:

```elixir
{:ok, result} = ClaudeCode.query("Summarize this PR",
  allowed_tools: ["Read", "Grep"]
)
```

Or use `ClaudeCode.start_link/1` with explicit lifecycle management:

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

### Pattern 2: Long-Running Sessions

Maintain persistent container instances for long-running tasks. Often running multiple Claude Agent processes inside the container based on demand.

Best for proactive agents that take action without user input, agents that serve content, or agents that process high volumes of messages.

**Examples:**
- **Email Agent:** Monitors incoming emails and autonomously triages, responds, or takes actions based on content
- **Site Builder:** Hosts custom websites per user with live editing capabilities served through container ports
- **High-Frequency Chat Bots:** Handles continuous message streams from platforms like Slack where rapid response times are critical

In Elixir, `ClaudeCode.Supervisor` manages named, long-lived sessions with automatic restart. This is useful for **dedicated single-purpose agents** like a CI bot or a background job processor -- cases where one caller owns the session at a time.

> **Caveat:** Each supervised session maintains conversation context across all queries. If multiple callers use the same named session concurrently, their queries serialize through the GenServer and share context, which fills the context window quickly with unrelated conversations. For multi-user workloads, prefer per-user or ephemeral sessions.

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

### Pattern 3: Hybrid Sessions

Ephemeral containers that are hydrated with history and state, possibly from a database or from the SDK's session resumption features.

Best for containers with intermittent interaction from the user that kicks off work and spins down when the work is completed but can be continued.

**Examples:**
- **Personal Project Manager:** Helps manage ongoing projects with intermittent check-ins, maintains context of tasks, decisions, and progress
- **Deep Research:** Conducts multi-hour research tasks, saves findings and resumes investigation when user returns
- **Customer Support Agent:** Handles support tickets that span multiple interactions, loads ticket history and customer context

In Elixir, use the `:resume` option with a stored session ID to restore conversation context:

```elixir
# Store session_id when stopping
session_id = ClaudeCode.get_session_id(session)
ClaudeCode.stop(session)

# Later, resume the conversation
{:ok, session} = ClaudeCode.start_link(resume: session_id)
```

### Pattern 4: Single Containers

Run multiple Claude Agent SDK processes in one global container.

Best for agents that must collaborate closely together. This is likely the least popular pattern because you will have to prevent agents from overwriting each other.

**Examples:**
- **Simulations:** Agents that interact with each other in simulations such as video games.

In Elixir, you can manage multiple sessions dynamically under a single supervisor:

```elixir
{:ok, supervisor} = ClaudeCode.Supervisor.start_link([])

# Add sessions on demand
ClaudeCode.Supervisor.start_session(supervisor, [
  name: :agent_alpha,
  system_prompt: "You are Agent Alpha."
])

ClaudeCode.Supervisor.start_session(supervisor, [
  name: :agent_beta,
  system_prompt: "You are Agent Beta."
])

# List active sessions
ClaudeCode.Supervisor.list_sessions(supervisor)

# Remove when done
ClaudeCode.Supervisor.terminate_session(supervisor, :agent_alpha)
```

## Elixir-Specific: Per-User Sessions

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

## Elixir-Specific: Releases

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

## Elixir-Specific: Resource Considerations

Each ClaudeCode session runs a separate CLI subprocess:

| Resource         | Per Session               |
| ---------------- | ------------------------- |
| OS process       | 1 Node.js process         |
| Memory           | ~50-100 MB                |
| File descriptors | 3 (stdin, stdout, stderr) |
| Ports            | 1 Erlang port             |

Plan accordingly when running multiple concurrent sessions. For workloads with many users but low concurrency, consider stopping idle sessions and resuming on demand with `resume: session_id`.

## Elixir-Specific: Health Monitoring

```elixir
defmodule MyApp.HealthCheck do
  def ai_status do
    sessions = ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)

    %{
      total: length(sessions),
      active: Enum.count(sessions, fn {_, pid, _, _} -> is_pid(pid) and Process.alive?(pid) end)
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

## FAQ

### How do I communicate with my sandboxes?

When hosting in containers, expose ports to communicate with your SDK instances. Your application can expose HTTP/WebSocket endpoints for external clients while the SDK runs internally within the container.

### What is the cost of hosting a container?

The dominant cost of serving agents is the tokens. Containers vary based on what you provision but a minimum cost is roughly 5 cents per hour running.

### When should I shut down idle containers vs. keeping them warm?

This is likely provider dependent. Different sandbox providers will let you set different criteria for idle timeouts after which a sandbox might spin down. You will want to tune this timeout based on how frequent you think user response might be.

### How often should I update the Claude Code CLI?

The Claude Code CLI is versioned with semver, so any breaking changes will be versioned. In the Elixir SDK, bump the `:cli_version` in your application config and run `mix claude_code.install` to update.

### How do I monitor container health and agent performance?

Since containers are just servers, the same logging infrastructure you use for the backend will work for containers. In Elixir, standard OTP logging via `Logger` and tools like Telemetry can monitor session lifecycle events.

### How long can an agent session run before timing out?

An agent session will not timeout, but we recommend setting the `:max_turns` option to prevent Claude from getting stuck in a loop.

## Next Steps

- [Secure Deployment](secure-deployment.md) - Network controls, credential management, and isolation hardening
- [Sessions](sessions.md) - Session management details
- [Permissions](permissions.md) - Configure tool permissions
- [Cost Tracking](cost-tracking.md) - Monitor API costs
- [MCP Integration](mcp.md) - Extend with custom tools
