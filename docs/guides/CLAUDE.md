# Guide Writing Rules

- Use full module names in prose so HexDocs auto-links them (e.g., `ClaudeCode.Stream.final_result/1`, not `final_result/1`).
- Check existing code before writing code snippets — ensure functions exist, use utility helpers whenever available, or if some use-cases seem very verbose, suggest adding a helper utility (e.g., `ClaudeCode.Stream` helpers).
- Use `ClaudeCode.Stream` helpers for common streaming operations (e.g., `ClaudeCode.Stream.final_result/1`).

## Based on Official Docs

- When a guide maps to an official Agent SDK page (`https://platform.claude.com/docs/en/agent-sdk/`), follow the official structure closely but prioritize idiomatic Elixir/OTP over a 1:1 translation of Python/TypeScript. If the official example uses a pattern that doesn't fit Elixir well, adapt it — don't force it.
- It is also important to include any relevant elixir-only guidance here as well, if it applies.
- For any functionality that is NOT complete in a guide, add a callout to the top of the guide to indicate that it is incomplete. If it is partially complete, indicate in the appropriate sections.

Each official-based guide should start with:

```markdown
# Title

Subtitle describing the guide.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/PAGE). Examples are adapted for Elixir.
```
