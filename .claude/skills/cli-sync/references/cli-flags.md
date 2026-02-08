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

## Always-Enabled Flags

These flags are always passed by the SDK (in `cli.ex`):

| Flag | Value | Reason |
|------|-------|--------|
| `--output-format` | `stream-json` | Required for JSON parsing |
| `--verbose` | (flag) | Get all message types |
| `--input-format` | `stream-json` | Bidirectional streaming |

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
| `:tool_callback` | Tool execution callback |
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

## Adding New Flags

When a new CLI flag is discovered:

### 1. Add to Schema

```elixir
# In @session_opts_schema:
new_flag: [type: :string, doc: "Description"]
```

### 2. Add Query Override (if applicable)

```elixir
# In @query_opts_schema:
new_flag: [type: :string, doc: "Override new_flag for this query"]
```

### 3. Add CLI Conversion

```elixir
# Boolean flag:
defp convert_option_to_cli_flag(:new_flag, true), do: ["--new-flag"]
defp convert_option_to_cli_flag(:new_flag, false), do: nil

# Value flag:
defp convert_option_to_cli_flag(:new_flag, value) do
  {"--new-flag", to_string(value)}
end

# List flag (comma-separated):
defp convert_option_to_cli_flag(:new_flag, value) when is_list(value) do
  {"--new-flag", Enum.join(value, ",")}
end

# List flag (repeated):
defp convert_option_to_cli_flag(:new_flag, value) when is_list(value) do
  Enum.flat_map(value, fn item -> ["--new-flag", to_string(item)] end)
end
```

## Flag Naming Conventions

| Pattern | Example |
|---------|---------|
| CLI kebab-case | `--max-turns` |
| Elixir snake_case | `:max_turns` |
| Boolean flags | No value, just flag presence |
| Value flags | `--flag VALUE` |
| Repeated flags | `--flag val1 --flag val2` |
| CSV flags | `--flag val1,val2,val3` |

## SDK Documentation URLs

For reference (may not be current):

- **TypeScript SDK**: https://platform.claude.com/docs/en/agent-sdk/typescript
- **Python SDK**: https://platform.claude.com/docs/en/agent-sdk/python
- **CLI Docs**: https://docs.anthropic.com/en/docs/claude-code

## Checking for New Flags

Run this to see all current CLI flags:

```bash
claude --help 2>&1 | grep -E '^\s+--'
```

Compare against `convert_option_to_cli_flag/2` patterns in `options.ex`.
