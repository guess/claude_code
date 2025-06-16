# 🤖 Claude Code SDK for Elixir

The most ergonomic way to integrate Claude AI into your Elixir applications.

- **🔄 Native Streaming**: Built on Elixir Streams for real-time responses
- **💬 Automatic Conversation Continuity**: Claude remembers context across queries
- **🏭 Production-Ready Supervision**: Fault-tolerant GenServers with automatic restarts
- **🛠️ Built-in File Operations**: Read, edit, and analyze files with zero configuration
- **⚡ High-Performance Concurrency**: Multiple concurrent sessions with Elixir's actor model
- **🔧 Zero-Config Phoenix Integration**: Drop-in support for LiveView and Phoenix apps

[![Hex.pm](https://img.shields.io/hexpm/v/claude_code.svg)](https://hex.pm/packages/claude_code)
[![Downloads](https://img.shields.io/hexpm/dt/claude_code.svg)](https://hex.pm/packages/claude_code)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/claude_code)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/guess/claude_code/blob/main/LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-%3E%3D1.14-purple.svg)](https://elixir-lang.org)

<div align="center">
    <img src="https://github.com/guess/claude_code/raw/main/docs/claudecode.png" alt="ClaudeCode" width="200">
</div>

## 🎯 30-Second Demo

```elixir
# Start a session and query Claude
{:ok, session} = ClaudeCode.start_link(api_key: "your-key")

# Real-time streaming responses
session
|> ClaudeCode.query_stream("Explain Elixir GenServers")
|> ClaudeCode.Stream.text_content()
|> Enum.each(&IO.write/1)  # Watch Claude type in real-time! 🎬

# Conversation continuity - Claude remembers context
ClaudeCode.query(session, "My favorite language is Elixir")
ClaudeCode.query(session, "What's my favorite language?")
# => "Your favorite language is Elixir!"
```

## 📦 Installation

**Step 1:** Add to your `mix.exs`
```elixir
def deps do
  [{:claude_code, "~> 0.2.0"}]
end
```

**Step 2:** Install dependencies
```bash
mix deps.get
```

**Step 3:** Get the Claude CLI
```bash
# Install from claude.ai/code
claude --version  # Verify installation
```

**Step 4:** Configure your API key
```elixir
# config/config.exs
config :claude_code, api_key: System.get_env("ANTHROPIC_API_KEY")
```

🎉 **Ready to go!** Try the quick demo above.

## ⚡ Quick Examples

```elixir
# Basic usage
{:ok, session} = ClaudeCode.start_link()
{:ok, response} = ClaudeCode.query(session, "Hello, Claude!")

# File operations
ClaudeCode.query(session, "Review my mix.exs file",
  allowed_tools: ["View", "Edit"])

# Production with supervision
{:ok, _} = ClaudeCode.Supervisor.start_link([
  [name: :assistant, api_key: api_key]
])
ClaudeCode.query(:assistant, "Help with this task")
```

📖 **[Complete Getting Started Guide →](docs/GETTING_STARTED.md)**

## 🚀 Key Features

- **💬 Conversation Continuity**: Claude remembers context across queries automatically
- **🔄 Real-time Streaming**: Watch responses appear in real-time with Elixir Streams
- **🛠️ File Operations**: Built-in tools for reading, editing, and analyzing files
- **🏭 Production Ready**: Fault-tolerant supervision with automatic restarts
- **⚡ High Performance**: Concurrent sessions for parallel processing
- **🔧 Phoenix Integration**: Drop-in compatibility with LiveView and Phoenix apps

## 🏭 Production Usage

### Supervised Sessions
```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    MyAppWeb.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :code_reviewer, api_key: api_key, system_prompt: "You review code"],
      [name: :general_assistant, api_key: api_key]
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
# Use in LiveViews and Controllers
def handle_event("ask_claude", %{"message" => message}, socket) do
  case ClaudeCode.query(:assistant, message) do
    {:ok, response} -> {:noreply, assign(socket, response: response)}
    {:error, _} -> {:noreply, put_flash(socket, :error, "Claude unavailable")}
  end
end
```

### Error Handling
```elixir
case ClaudeCode.query(session, "Hello") do
  {:ok, response} -> IO.puts(response)
  {:error, :timeout} -> IO.puts("Request timed out")
  {:error, {:cli_not_found, msg}} -> IO.puts("CLI error: #{msg}")
  {:error, {:claude_error, msg}} -> IO.puts("Claude error: #{msg}")
end
```

## 📚 Documentation

- 🚀 **[Getting Started](docs/GETTING_STARTED.md)** - Step-by-step tutorial for new users
- 🏭 **[Production Guide](docs/SUPERVISION.md)** - Fault-tolerant production deployments
- 💻 **[Examples](docs/EXAMPLES.md)** - Real-world usage patterns and code samples
- 📖 **[API Reference](https://hexdocs.pm/claude_code)** - Complete API documentation
- 🔧 **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## 🤝 Contributing

We ❤️ contributions! Whether it's:

- 🐛 **Bug reports** - Found an issue? Let us know!
- 💡 **Feature requests** - Have an idea? We'd love to hear it!
- 📝 **Documentation** - Help make our docs even better
- 🔧 **Code contributions** - PRs welcome!

See our [Contributing Guide](CONTRIBUTING.md) to get started.

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

MIT License - see [LICENSE](LICENSE) for details.

---

**Built on top of the [Claude Code CLI](https://github.com/anthropics/claude-code) and designed for the Elixir community.**

*Made with ❤️ for Elixir developers who want the best AI integration experience.*
