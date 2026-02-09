# Overview

The ClaudeCode Elixir SDK provides an idiomatic Elixir interface to the Claude Code CLI. It spawns `claude` as a subprocess and communicates via streaming JSON, giving you full access to Claude's agentic capabilities from Elixir applications.

## Core API

```elixir
# One-off query
{:ok, result} = ClaudeCode.query("Explain pattern matching in Elixir")
IO.puts(result)

# Multi-turn conversation
{:ok, session} = ClaudeCode.start_link(model: "sonnet")

ClaudeCode.stream(session, "Create a GenServer for a counter")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stream(session, "Add a reset function")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)

ClaudeCode.stop(session)
```

## Capabilities

| Capability | Elixir API |
|-----------|-----------|
| Single queries | `ClaudeCode.query/2` |
| Streaming | `ClaudeCode.stream/3` + `ClaudeCode.Stream` utilities |
| Multi-turn conversations | Persistent sessions via `start_link/1` |
| Tool control | `allowed_tools:`, `disallowed_tools:`, `tools:` |
| Tool monitoring | `tool_callback:` option |
| Custom agents | `agents:` option |
| MCP servers | `mcp_servers:` with Hermes modules or external commands |
| Permissions | `permission_mode:` option |
| Session management | `get_session_id/1`, `resume:`, `fork_session:`, `clear/1` |
| Structured output | `output_format:` with JSON Schema |
| System prompts | `system_prompt:`, `append_system_prompt:` |
| Supervision | `ClaudeCode.Supervisor` for fault-tolerant deployments |

## How It Works

The SDK manages Claude Code CLI subprocesses:

1. **`ClaudeCode.start_link/1`** starts a GenServer that spawns the CLI with `--input-format stream-json --output-format stream-json --verbose`
2. **`ClaudeCode.stream/3`** sends a prompt via stdin and returns an Elixir `Stream` of parsed messages
3. Messages are emitted as structs: `SystemMessage`, `AssistantMessage`, `UserMessage`, `ResultMessage`
4. The CLI handles all API communication, tool execution, and permission management

```
Your App  <-->  ClaudeCode Session (GenServer)  <-->  Claude CLI (Port)  <-->  Claude API
```

## Elixir SDK vs Direct API vs CLI

| | Elixir SDK | Direct API | CLI |
|-|-----------|-----------|-----|
| Tool execution | Built-in (Read, Write, Bash, etc.) | Manual implementation | Built-in |
| Multi-turn | Automatic via sessions | Manual context management | Manual |
| Streaming | Native Elixir Streams | HTTP SSE parsing | JSON lines |
| Supervision | OTP supervision trees | Custom implementation | N/A |
| Concurrency | Multiple supervised sessions | Manual | Single process |

## OTP Advantages

The Elixir SDK leverages OTP for production reliability:

- **Supervision trees** restart crashed sessions automatically
- **Named processes** allow accessing sessions from anywhere in your app
- **Concurrent sessions** run independently with separate CLI subprocesses
- **Graceful shutdown** via standard OTP shutdown sequences
- **Dynamic scaling** with `ClaudeCode.Supervisor.start_session/3`

```elixir
# Production supervision tree
children = [
  {ClaudeCode.Supervisor, [
    [name: :code_reviewer, system_prompt: "You review Elixir code"],
    [name: :test_writer, system_prompt: "You write ExUnit tests"]
  ]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Next Steps

- [Quickstart](quickstart.md) - Installation and first query
- [Streaming vs Single Mode](streaming-vs-single-mode.md) - Choose the right API
- [Sessions](sessions.md) - Multi-turn conversation management
