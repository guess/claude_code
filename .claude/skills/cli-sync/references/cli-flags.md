# CLI Flags Reference

Mapping between CLI flags, Elixir options, and implementation details.

## Implemented Flags

| CLI Flag | Elixir Option | Type | Notes |
|----------|---------------|------|-------|
| `--model` | `:model` | string | Model to use |
| `--fallback-model` | `:fallback_model` | string | Fallback if primary fails |
| `--system-prompt` | `:system_prompt` | string | Override system prompt |
| `--append-system-prompt` | `:append_system_prompt` | string | Append to system prompt |
| `--max-turns` | `:max_turns` | integer | Limit agentic turns |
| `--max-budget-usd` | `:max_budget_usd` | float | Maximum API cost |
| `--max-thinking-tokens` | `:max_thinking_tokens` | integer | Extended thinking limit |
| `--agent` | `:agent` | string | Agent name to use |
| `--betas` | `:betas` | list | Beta headers (repeatable) |
| `--tools` | `:tools` | string | Tools: "default", "", or list |
| `--allowedTools` | `:allowed_tools` | list | Allowed tools (CSV) |
| `--disallowedTools` | `:disallowed_tools` | list | Disallowed tools (CSV) |
| `--add-dir` | `:add_dir` | list | Additional directories (repeatable) |
| `--mcp-config` | `:mcp_config` | string | MCP config file path |
| `--mcp-config` | `:mcp_servers` | map | Inline MCP config (JSON) |
| `--strict-mcp-config` | `:strict_mcp_config` | boolean | Only use explicit MCP config |
| `--permission-prompt-tool` | `:permission_prompt_tool` | string | MCP permission tool |
| `--permission-mode` | `:permission_mode` | atom | Permission handling mode |
| `--json-schema` | `:output_format` | map | Structured output schema |
| `--settings` | `:settings` | string/map | Settings config |
| `--setting-sources` | `:setting_sources` | list | Setting sources (CSV) |
| `--plugin-dir` | `:plugins` | list | Plugin directories (repeatable) |
| `--agents` | `:agents` | map | Custom agent definitions (JSON) |
| `--effort` | `:effort` | atom | Effort level (:low, :medium, :high) |
| `--continue` | `:continue` | boolean | Continue last conversation |
| `--fork-session` | `:fork_session` | boolean | Fork when resuming |
| `--include-partial-messages` | `:include_partial_messages` | boolean | Enable partial streaming |
| `--disable-slash-commands` | `:disable_slash_commands` | boolean | Disable skills |
| `--no-session-persistence` | `:no_session_persistence` | boolean | Don't persist session |
| `--session-id` | `:session_id` | string | Specific session ID |
| `--file` | `:file` | list | File resources (repeatable, format: file_id:path) |
| `--from-pr` | `:from_pr` | string/integer | Resume session linked to PR |
| `--debug` | `:debug` | boolean/string | Debug mode with optional filter |
| `--debug-file` | `:debug_file` | string | Debug log file path |
| `--system-prompt-file` | `:system_prompt_file` | string | System prompt from file |
| `--append-system-prompt-file` | `:append_system_prompt_file` | string | Append system prompt from file |
| `--bare` | `:bare` | boolean | Skip hooks/LSP/plugins for fast scripted sessions |
| `--worktree` | `:worktree` | boolean/string | Git worktree support |

## Always-Enabled Flags

These flags are always passed by the SDK (in `cli.ex`) and should NOT be added to `options.ex`:

| Flag | Value | Reason |
|------|-------|--------|
| `--output-format` | `stream-json` | Required for JSON parsing |
| `--verbose` | (flag) | Required for streaming - get all message types |
| `--input-format` | `stream-json` | Bidirectional streaming |

**Note**: When `claude --help` shows `--verbose` as an option, ignore it during options comparison. The SDK always enables verbose mode because it's required for streaming to work properly. It is not user-configurable.

## Elixir-Only Options

Options handled by the Elixir SDK, not passed to CLI:

| Option | Purpose |
|--------|---------|
| `:api_key` | Set via ANTHROPIC_API_KEY env var |
| `:name` | GenServer process name |
| `:timeout` | Query timeout in ms |
| `:cli_path` | Custom CLI binary path |
| `:resume` | Session ID to resume (passed differently) |
| `:adapter` | Test adapter configuration |
| `:env` | Additional environment variables |

## Permission Mode Values

| Elixir Atom | CLI Value |
|-------------|-----------|
| `:default` | `default` |
| `:accept_edits` | `acceptEdits` |
| `:bypass_permissions` | `bypassPermissions` |
| `:delegate` | `delegate` |
| `:dont_ask` | `dontAsk` |
| `:plan` | `plan` |

