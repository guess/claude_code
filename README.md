# 🤖 Claude Code SDK for Elixir

The idiomatic way to integrate Claude AI into your Elixir applications.

- **🔄 Native Streaming**: Built on Elixir Streams for real-time responses
- **💬 Conversation Continuity**: Automatic context retention across queries
- **🔁 Bidirectional Streaming**: Multi-turn conversations over a single connection
- **🏭 Production-Ready Supervision**: Fault-tolerant GenServers with automatic restarts
- **🛠️ Built-in File Operations**: Read, edit, and analyze files with zero configuration
- **⚡ High-Performance Concurrency**: Multiple concurrent sessions with Elixir's actor model
- **🔧 Zero-Config Phoenix Integration**: Drop-in support for LiveView and Phoenix apps

[![Hex.pm](https://img.shields.io/hexpm/v/claude_code.svg)](https://hex.pm/packages/claude_code)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/claude_code)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/guess/claude_code/blob/main/LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-%3E%3D1.18-purple.svg)](https://elixir-lang.org)

<div align="center">
    <img src="https://github.com/guess/claude_code/raw/main/docs/claudecode.png" alt="ClaudeCode" width="200">
</div>

## 🎯 30-Second Demo

```elixir
# Start a session and query Claude (uses ANTHROPIC_API_KEY from env)
{:ok, session} = ClaudeCode.start_link()
{:ok, response} = ClaudeCode.query(session, "Explain Elixir GenServers in one sentence")
IO.puts(response)

# Conversation continuity - Claude remembers context
ClaudeCode.query(session, "My favorite language is Elixir")
{:ok, answer} = ClaudeCode.query(session, "What's my favorite language?")
IO.puts(answer)  # => "Your favorite language is Elixir!"
```

## 📦 Installation

**Step 1:** Add to your `mix.exs`
```elixir
def deps do
  [{:claude_code, "~> 0.6.0"}]
end
```

**Step 2:** Install dependencies
```bash
mix deps.get
```

**Step 3:** Get the Claude CLI
```bash
# Install the Claude Code CLI: https://docs.anthropic.com/en/docs/claude-code
claude --version  # Verify installation
```

**Step 4:** Set your API key
```bash
# The SDK uses ANTHROPIC_API_KEY from your environment
export ANTHROPIC_API_KEY="sk-ant-your-api-key-here"

# Or configure in config/config.exs (optional)
config :claude_code, api_key: System.get_env("ANTHROPIC_API_KEY")
```

🎉 **Ready to go!** Try the quick demo above.

## ⚡ Quick Examples

```elixir
# Basic usage (uses ANTHROPIC_API_KEY from environment)
{:ok, session} = ClaudeCode.start_link()
{:ok, response} = ClaudeCode.query(session, "Hello, Claude!")

# File operations
ClaudeCode.query(session, "Review my mix.exs file",
  allowed_tools: ["View", "Edit"])

# Custom agents
agents = %{
  "code-reviewer" => %{
    "description" => "Expert code reviewer. Use proactively after code changes.",
    "prompt" => "You are a senior code reviewer. Focus on quality and best practices.",
    "tools" => ["Read", "Grep", "Glob"],
    "model" => "sonnet"
  }
}
{:ok, session} = ClaudeCode.start_link(agents: agents)

# Production with supervision
{:ok, _} = ClaudeCode.Supervisor.start_link(name: :assistant)
ClaudeCode.query(:assistant, "Help with this task")
```

📖 **[Complete Getting Started Guide →](docs/guides/getting-started.md)**

## 🏭 Production Usage

### Supervised Sessions
```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    MyAppWeb.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :code_reviewer, system_prompt: "You review code"],
      [name: :general_assistant]
    ]}
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end

# Use from anywhere in your app
{:ok, review} = ClaudeCode.query(:code_reviewer, "Review this code")
```

**Benefits:**
- ✅ **Fault tolerance** - Sessions restart automatically on crashes
- ✅ **Zero downtime** - Hot code reloading preserves session state
- ✅ **Global access** - Named sessions work from anywhere in your app
- ✅ **Distributed support** - Sessions work across Elixir clusters

### Phoenix Integration
```elixir
# Simple controller usage
def ask(conn, %{"prompt" => prompt}) do
  case ClaudeCode.query(:assistant, prompt) do
    {:ok, response} -> json(conn, %{response: response})
    {:error, _} -> json(conn, %{error: "Claude unavailable"})
  end
end
```

For LiveView with real-time streaming, use `query_stream/3` with a Task:
```elixir
# LiveView with streaming responses
def handle_event("send", %{"message" => msg}, socket) do
  parent = self()
  Task.start(fn ->
    :assistant
    |> ClaudeCode.query_stream(msg, include_partial_messages: true)
    |> ClaudeCode.Stream.text_deltas()
    |> Enum.each(&send(parent, {:chunk, &1}))
    send(parent, :complete)
  end)
  {:noreply, assign(socket, streaming: true)}
end

def handle_info({:chunk, chunk}, socket) do
  {:noreply, assign(socket, response: socket.assigns.response <> chunk)}
end

def handle_info(:complete, socket) do
  {:noreply, assign(socket, streaming: false)}
end
```

📖 **[Full Phoenix Integration Guide →](docs/integration/phoenix.md)**

### Error Handling
```elixir
case ClaudeCode.query(session, "Hello") do
  {:ok, response} -> IO.puts(response)
  {:error, :timeout} -> IO.puts("Request timed out")
  {:error, {:cli_not_found, msg}} -> IO.puts("CLI error: #{msg}")
  {:error, {:claude_error, msg}} -> IO.puts("Claude error: #{msg}")
end
```

### Multi-turn Conversations
Sessions automatically maintain context across queries:
```elixir
{:ok, session} = ClaudeCode.start_link()

# First turn
{:ok, response1} = ClaudeCode.query(session, "What's the capital of France?")
IO.puts(response1)  # Paris

# Second turn - context is preserved automatically
{:ok, response2} = ClaudeCode.query(session, "What about Germany?")
IO.puts(response2)  # Berlin

# Get session ID for later resume
{:ok, session_id} = ClaudeCode.get_session_id(session)

ClaudeCode.stop(session)

# Resume later with the same context
{:ok, new_session} = ClaudeCode.start_link(resume: session_id)
{:ok, response3} = ClaudeCode.query(new_session, "What was the first capital I asked about?")
IO.puts(response3)  # Paris
```

**Benefits:**
- ✅ **Persistent connection** - Single CLI process handles all queries
- ✅ **Auto-connect/disconnect** - No manual lifecycle management
- ✅ **Resume support** - Continue previous conversations with `resume: session_id`
- ✅ **Lower latency** - No startup overhead between turns

### Tool Callbacks
Monitor tool executions for logging, auditing, or analytics:
```elixir
callback = fn event ->
  Logger.info("Tool #{event.name} executed",
    input: event.input,
    result: event.result,
    is_error: event.is_error
  )
end

{:ok, session} = ClaudeCode.start_link(tool_callback: callback)
```

### MCP Integration (Optional)
Expose Elixir tools to Claude using Hermes MCP:
```elixir
# Add {:hermes_mcp, "~> 0.14"} to your deps

# Start MCP server with your tools
{:ok, config_path} = ClaudeCode.MCP.Server.start_link(
  server: MyApp.MCPServer,
  port: 9001
)

# Connect ClaudeCode to MCP server
{:ok, session} = ClaudeCode.start_link(mcp_config: config_path)

# Claude can now use your custom tools!
```

## 📚 Documentation

- 🚀 **[Getting Started](docs/guides/getting-started.md)** - Step-by-step tutorial for new users
- 📖 **[Documentation Hub](docs/README.md)** - All guides and references
- 🏭 **[Production Guide](docs/advanced/supervision.md)** - Fault-tolerant production deployments
- 💻 **[Examples](docs/reference/examples.md)** - Real-world usage patterns and code samples
- 📖 **[API Reference](https://hexdocs.pm/claude_code)** - Complete API documentation
- 🔧 **[Troubleshooting](docs/reference/troubleshooting.md)** - Common issues and solutions

## 🤝 Contributing

We ❤️ contributions! Whether it's:

- 🐛 **Bug reports** - Found an issue? Let us know!
- 💡 **Feature requests** - Have an idea? We'd love to hear it!
- 📝 **Documentation** - Help make our docs even better
- 🔧 **Code contributions** - PRs welcome!

See our [Contributing Guide](https://github.com/guess/claude_code/blob/main/CONTRIBUTING.md) to get started.

## 🛠️ Development

```bash
# Clone and setup
git clone https://github.com/guess/claude_code.git
cd claude_code
mix deps.get

# Run tests and quality checks
mix test
mix quality  # format, credo, dialyzer
```

## 📜 License

MIT License - see [LICENSE](https://github.com/guess/claude_code/blob/main/LICENSE) for details.

---

**Built for Elixir developers on top of the [Claude Code CLI](https://github.com/anthropics/claude-code).**
