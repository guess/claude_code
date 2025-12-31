# Contributing to ClaudeCode

We love contributions from the community! Whether you're fixing bugs, adding features, improving documentation, or reporting issues, your help makes ClaudeCode better for everyone.

## 🚀 Quick Start

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/your-username/claude_code.git
   cd claude_code
   ```
3. **Install dependencies**:
   ```bash
   mix deps.get
   ```
4. **Run tests** to make sure everything works:
   ```bash
   mix test
   ```

## 🛠️ Development Workflow

### Setting up Your Environment

1. **Elixir Version**: This project requires Elixir >= 1.18
2. **Claude CLI**: Install the Claude Code CLI from [claude.ai/code](https://claude.ai/code)
3. **API Key**: You'll need an Anthropic API key for integration tests

### Making Changes

1. **Create a branch** for your feature:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Write tests first** (TDD approach):
   ```bash
   # Add tests in test/ directory
   mix test test/path/to/your_test.exs
   ```

3. **Implement your changes** following the existing code style

4. **Run quality checks**:
   ```bash
   mix quality  # Runs format, credo, and dialyzer
   ```

5. **Update documentation** if needed:
   ```bash
   mix docs  # Generate local docs to verify
   ```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/claude_code/session_test.exs

# Run tests with coverage
mix test.all

# Generate HTML coverage report
mix coveralls.html
```

### Test Structure

- **Unit tests** - Mock the Port for predictable behavior
- **Integration tests** - Use mock CLI script when real CLI unavailable
- **Property tests** - Use StreamData for message parsing validation

### Writing Tests

Follow the existing patterns:

```elixir
defmodule ClaudeCode.YourModuleTest do
  use ExUnit.Case, async: true
  
  describe "your_function/1" do
    test "handles expected input correctly" do
      # Test implementation
    end
    
    test "handles edge cases" do
      # Test edge cases
    end
  end
end
```

## 📝 Code Style

### Formatting

We use [Styler](https://github.com/adobe/elixir-styler) for code formatting:

```bash
mix format  # Format all code
```

### Code Quality

Run these checks before submitting:

```bash
mix credo --strict  # Static code analysis
mix dialyzer        # Type checking
```

### Documentation

- All public functions need `@doc` strings
- Use doctests where appropriate:

```elixir
@doc """
Example function that does something useful.

## Examples

    iex> ClaudeCode.YourModule.your_function("input")
    {:ok, "output"}

"""
def your_function(input) do
  # Implementation
end
```

## 🐛 Reporting Issues

When reporting bugs, please include:

1. **Elixir version**: `elixir --version`
2. **ClaudeCode version**: Check your `mix.exs`
3. **Claude CLI version**: `claude --version`
4. **Reproduction steps**: Minimal code example
5. **Expected vs actual behavior**
6. **Error messages** if any

## 💡 Feature Requests

Before requesting features:

1. **Check existing issues** to avoid duplicates
2. **Describe the use case** - why is this needed?
3. **Propose a solution** if you have ideas
4. **Consider the scope** - does it fit the project goals?

## 📋 Pull Request Process

### Before Submitting

- [ ] Tests pass: `mix test`
- [ ] Quality checks pass: `mix quality`
- [ ] Documentation updated if needed
- [ ] CHANGELOG.md updated for notable changes
- [ ] Follows existing code patterns

### PR Description

Include:

1. **What** - What does this PR do?
2. **Why** - Why is this change needed?
3. **How** - How does it work?
4. **Testing** - How was it tested?

Example:
```markdown
## What
Adds streaming support for real-time responses.

## Why
Users want to see Claude's responses as they're generated, like in the web interface.

## How
- Implements `query_stream/3` function
- Uses Elixir Streams for lazy evaluation
- Parses JSON messages in real-time

## Testing
- Added unit tests for stream parsing
- Added integration test with mock CLI
- Tested with real Claude CLI manually
```

### Review Process

1. **Automated checks** must pass (CI)
2. **Code review** by maintainers
3. **Testing** on different environments
4. **Merge** when approved

## 🏗️ Project Architecture

Understanding the codebase:

- **`lib/claude_code.ex`** - Main API module
- **`lib/claude_code/session.ex`** - GenServer managing CLI subprocess
- **`lib/claude_code/cli.ex`** - CLI binary detection and command building
- **`lib/claude_code/options.ex`** - Options validation with NimbleOptions
- **`lib/claude_code/message/`** - Message type parsing
- **`lib/claude_code/content/`** - Content block parsing
- **`lib/claude_code/stream.ex`** - Stream utilities

See `docs/ARCHITECTURE.md` for detailed architecture information.

## 📚 Development Resources

- **CLAUDE.md** - Project-specific development guidance
- **docs/ROADMAP.md** - Future plans and current phase
- **docs/VISION.md** - Project goals and philosophy
- **HexDocs** - Generated documentation at `/doc/index.html`

## 🔄 Release Process

Releases are handled by maintainers:

1. Update version in `mix.exs`
2. Update `CHANGELOG.md`
3. Create git tag
4. Publish to Hex.pm

## 🤝 Community Guidelines

- **Be respectful** and inclusive
- **Help newcomers** get started
- **Share knowledge** through issues and discussions
- **Follow** the [Elixir Community Code of Conduct](https://elixir-lang.org/community.html#code-of-conduct)

## 🎯 Good First Issues

Look for issues labeled:
- `good first issue` - Perfect for newcomers
- `help wanted` - Community contributions welcome
- `documentation` - Improve docs and examples

## 📞 Getting Help

- **Issues** - For bugs and feature requests
- **Discussions** - For questions and community chat
- **Discord/Slack** - Real-time community support (if available)

---

Thank you for contributing to ClaudeCode! Every contribution, no matter how small, helps make the Elixir ecosystem better. 🎉