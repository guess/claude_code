# P2: Claude Subscription OAuth Support

**Priority**: P2 (Nice to have)
**Status**: 📋 Planned
**Effort**: ~2 hours

## Overview

Support Claude subscriptions via OAuth tokens as an alternative to API keys. This enables users with Claude subscriptions to use the SDK without requiring a separate Anthropic API key.

## Motivation

The Claude CLI supports two authentication methods:
1. **API Key** via `ANTHROPIC_API_KEY` environment variable (current SDK requirement)
2. **OAuth Token** via `CLAUDE_CODE_OAUTH_TOKEN` environment variable (subscription-based)

Currently, the SDK requires `:api_key` to be provided. Users with Claude subscriptions should be able to use their subscription credentials instead.

## Requirements

### Must Have
- Detect `CLAUDE_CODE_OAUTH_TOKEN` in environment variables
- Make `:api_key` option optional when OAuth token is present
- Update validation to accept either API key or OAuth token
- Document OAuth authentication method

### Nice to Have
- Explicit `:oauth_token` option to override environment variable
- Clear error messages when neither auth method is available
- Validation that only one auth method is active at a time

## Implementation Plan

### 1. Update Options Schema

```elixir
# lib/claude_code/options.ex

# Make :api_key optional
@session_schema [
  api_key: [
    type: :string,
    doc: "Anthropic API key. Optional if CLAUDE_CODE_OAUTH_TOKEN is set.",
    # Remove :required from keys
  ],
  oauth_token: [
    type: :string,
    doc: "Claude Code OAuth token. Defaults to CLAUDE_CODE_OAUTH_TOKEN env var.",
  ],
  # ... rest of schema
]

# Add validation function
defp validate_authentication(opts) do
  api_key = opts[:api_key]
  oauth_token = opts[:oauth_token] || System.get_env("CLAUDE_CODE_OAUTH_TOKEN")

  cond do
    api_key && oauth_token ->
      {:error, "Cannot use both :api_key and :oauth_token"}

    api_key || oauth_token ->
      :ok

    true ->
      {:error, "Either :api_key or CLAUDE_CODE_OAUTH_TOKEN environment variable is required"}
  end
end
```

### 2. Update CLI Module

```elixir
# lib/claude_code/cli.ex

def build_command(prompt, opts) do
  # ... existing code ...

  env =
    case {opts[:api_key], opts[:oauth_token]} do
      {nil, oauth} when is_binary(oauth) ->
        [{"CLAUDE_CODE_OAUTH_TOKEN", oauth}]

      {api_key, _} when is_binary(api_key) ->
        [{"ANTHROPIC_API_KEY", api_key}]

      _ ->
        # Rely on environment variables already set
        []
    end

  {cmd, env}
end
```

### 3. Update Session Module

```elixir
# lib/claude_code/session.ex

def start_link(opts) do
  with {:ok, validated_opts} <- Options.validate_session_opts(opts),
       :ok <- Options.validate_authentication(validated_opts) do
    GenServer.start_link(__MODULE__, validated_opts, name: via(validated_opts[:name]))
  end
end
```

### 4. Documentation Updates

- Add OAuth authentication section to main README
- Update `ClaudeCode.Options` module docs
- Add example showing OAuth usage
- Document precedence: explicit option > environment variable

## Testing Strategy

```elixir
# test/claude_code/options_test.exs

describe "authentication validation" do
  test "accepts API key" do
    opts = [api_key: "sk-ant-test"]
    assert :ok = Options.validate_authentication(opts)
  end

  test "accepts OAuth token from option" do
    opts = [oauth_token: "oauth-token-test"]
    assert :ok = Options.validate_authentication(opts)
  end

  test "accepts OAuth token from environment" do
    System.put_env("CLAUDE_CODE_OAUTH_TOKEN", "oauth-env-test")
    opts = []
    assert :ok = Options.validate_authentication(opts)
  after
    System.delete_env("CLAUDE_CODE_OAUTH_TOKEN")
  end

  test "rejects both API key and OAuth token" do
    opts = [api_key: "sk-ant-test", oauth_token: "oauth-test"]
    assert {:error, _} = Options.validate_authentication(opts)
  end

  test "rejects neither auth method" do
    opts = []
    assert {:error, _} = Options.validate_authentication(opts)
  end
end
```

## Edge Cases

1. **Both credentials provided**: Error - only one authentication method allowed
2. **Neither credential**: Error - at least one required
3. **OAuth token in env + API key in option**: API key takes precedence (explicit > implicit)
4. **Empty string credentials**: Treat as missing, not present

## Documentation Example

```elixir
# Using API key (current method)
{:ok, session} = ClaudeCode.Session.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# Using OAuth token from environment
{:ok, session} = ClaudeCode.Session.start_link([])  # Reads CLAUDE_CODE_OAUTH_TOKEN

# Using explicit OAuth token
{:ok, session} = ClaudeCode.Session.start_link(
  oauth_token: "oauth-token-here"
)
```

## Success Criteria

- ✅ Users can authenticate with OAuth tokens
- ✅ Existing API key authentication still works
- ✅ Clear error messages for auth configuration issues
- ✅ Documentation updated with OAuth examples
- ✅ Tests cover all authentication scenarios

## Non-Goals

- OAuth token acquisition/refresh (handled by Claude CLI setup)
- Token validation (delegated to CLI)
- Multiple credential fallback chains

## Open Questions

1. Should we support both credentials and auto-select? **No** - explicit is better
2. Should OAuth option override API key if both present? **Yes** - explicit option wins
3. Do we need a `:prefer_oauth` flag? **No** - keep it simple

## Related Work

- CLI authentication: `setup-token` command (out of SDK scope)
- Environment variable precedence: follows Claude CLI conventions
- API key handling: existing implementation (no changes needed)

---

**Next Steps**: Add to v1.1 roadmap as P2 feature after v1.0 release
