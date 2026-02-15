# ClaudeCode Documentation

Welcome to the ClaudeCode Elixir SDK documentation.

## Getting Started


## Core Guides

### Queries and Streaming
- **[Streaming vs Single Mode](guides/streaming-vs-single-mode.md)** - `query/2` vs `stream/3`
- **[Streaming Output](guides/streaming-output.md)** - Character-level deltas and partial messages
- **[Stop Reasons](guides/stop-reasons.md)** - Understanding result message subtypes
- **[Structured Outputs](guides/structured-outputs.md)** - JSON Schema-based structured responses

### Sessions and State
- **[Sessions](guides/sessions.md)** - Multi-turn conversations, resume, fork, and history
- **[User Input](guides/user-input.md)** - Tool approvals, clarifying questions, and user input
- **[File Checkpointing](guides/file-checkpointing.md)** - Track file changes during sessions

### Permissions and Security
- **[Permissions](guides/permissions.md)** - Tool restrictions and permission modes
- **[Secure Deployment](guides/secure-deployment.md)** - Sandboxing and production security

### Customization
- **[Modifying System Prompts](guides/modifying-system-prompts.md)** - System prompts and settings
- **[Hooks](guides/hooks.md)** - Tool execution monitoring and callbacks
- **[Cost Tracking](guides/cost-tracking.md)** - Usage monitoring and budget controls

### Tools and Extensions
- **[MCP](guides/mcp.md)** - Model Context Protocol server integration
- **[Custom Tools](guides/custom-tools.md)** - Building tools with Hermes MCP
- **[Subagents](guides/subagents.md)** - Custom agent definitions
- **[Slash Commands](guides/slash-commands.md)** - Predefined prompt commands
- **[Skills](guides/skills.md)** - Project-level skills
- **[Plugins](guides/plugins.md)** - Plugin configuration

### Production
- **[Hosting](guides/hosting.md)** - OTP supervision and deployment
- **[Testing](reference/testing.md)** - Testing with the ClaudeCode test adapter

## Integration

- **[Phoenix](integration/phoenix.md)** - LiveView streaming, controllers, and PubSub
- **[Hooks](guides/hooks.md)** - Monitoring and auditing tool executions

## Advanced

- **`ClaudeCode.Options`** - All options and precedence rules
- **[Hosting](guides/hosting.md)** - Fault-tolerant production deployments
- **[Subagents](guides/subagents.md)** - Custom agent configurations

## Reference

- **[Examples](reference/examples.md)** - Code patterns and recipes
- **[Troubleshooting](reference/troubleshooting.md)** - Common issues and solutions

## Quick Links

- [Main README](../README.md)
- [API Reference](https://hexdocs.pm/claude_code)
- [Changelog](../CHANGELOG.md)
- [GitHub](https://github.com/guess/claude_code)

## Reading Order

If you're new to ClaudeCode:

1. [Streaming vs Single Mode](guides/streaming-vs-single-mode.md) - Choose the right API
2. [Sessions](guides/sessions.md) - Multi-turn conversations
3. [Streaming Output](guides/streaming-output.md) - Real-time responses
4. [Permissions](guides/permissions.md) - Control tool access
5. [Hosting](guides/hosting.md) - Production deployment
