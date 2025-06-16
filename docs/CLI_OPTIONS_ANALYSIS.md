# CLI Options Analysis

This document compares the CLI options available in the `claude` command with our Elixir SDK implementation to identify gaps and necessary changes.

## CLI Options from `claude --help`

### Options We Support ✅

| CLI Flag | SDK Option | Notes |
|----------|------------|-------|
| `--print, -p` | Always added | Required for non-interactive mode |
| `--output-format` | Always `stream-json` | Required for JSON streaming |
| `--verbose` | Always added | Required for all message types |
| `--model` | `:model` | Supported |
| `--allowedTools` | `:allowed_tools` | List converted to CSV |
| `--disallowedTools` | `:disallowed_tools` | List converted to CSV |
| `--mcp-config` | `:mcp_config` | Supported |
| `--permission-prompt-tool` | Only supported with `--print` flag (which we use) |
| `--dangerously-skip-permissions` | Bypass permission checks | High (security feature) |
| `--add-dir` | Additional directories for tool access | Medium |

### Options We Have But CLI Doesn't Support ❌

| SDK Option | Issue |
|------------|-------|
| `:cwd` | CLI doesn't have `--cwd` flag (might use working directory differently) |
| `:timeout` | CLI doesn't have this flag - internal to SDK |

### CLI Options We're Missing 🚧

| CLI Flag | Description | Priority |
|----------|-------------|----------|
| `--continue, -c` | Continue most recent conversation | High (useful feature) |
| `--resume, -r` | Resume conversation by ID | High (useful feature) |

## Action Plan

### 1. Remove/Fix Unsupported Options

- **`:cwd`** - Need to investigate how CLI handles working directory
  - Option 1: Remove from SDK if not supported
  - Option 2: Use `cd` before running command if needed
  - Option 3: Check if it's an environment variable instead

- **`:timeout`** - Internal SDK option
  - Keep as Elixir-specific option, don't pass to CLI

### 2. Add Missing CLI Options

#### High Priority
- **`:debug`** - Add support for debug mode
  ```elixir
  debug: [type: :boolean, default: false, doc: "Enable debug mode"]
  ```

#### Session Management (Internal Implementation)
- **`:continue`** and **`:resume`** - Should NOT be exposed as user options
  - See "Session Continuity Strategy" section below

#### Medium Priority
- **`:add_dir`** - Additional directory access
  ```elixir
  add_dir: [type: {:list, :string}, doc: "Additional directories for tool access"]
  ```

### 3. Fix Option Mappings

- **Tool lists** - Currently converted to CSV correctly ✅
- **Flag naming** - Need to ensure proper kebab-case conversion
  - `allowed_tools` → `--allowedTools` (not kebab-case!)
  - `disallowed_tools` → `--disallowedTools` (not kebab-case!)

### 4. Special Handling Required

- **Session Management** - Handled internally, no user-facing options needed

## Implementation Steps

1. **Update `options.ex`** schema to add missing options
2. **Fix flag name conversion** for camelCase CLI flags (allowedTools, disallowedTools)
3. **Remove or document** unsupported options (`:cwd`, `:permission_mode`)
4. **Add validation** for mutually exclusive options
5. **Update tests** to cover new options
6. **Document** any SDK-specific options that don't map to CLI

## Questions to Investigate

1. Is `--cwd` supported but undocumented?
2. Is `--permission-mode` a real flag or should we remove it?
3. How does the CLI handle working directory changes?
4. Should we support `--input-format stream-json` for future features?

## Session Continuity Strategy

### Current State
- The CLI already sends `session_id` in System, Assistant, and Result messages
- We parse and capture these session IDs but don't store them
- Each query spawns a new CLI subprocess with no session memory

### Proposed Implementation: Automatic Session Continuity

#### Core Principle: Conversations Continue by Default
Just like the interactive CLI, conversations should naturally continue unless explicitly cleared. This matches user expectations and provides a more intuitive experience.

#### 1. Store Session ID in GenServer State
```elixir
defmodule ClaudeCode.Session do
  defstruct [
    :api_key,
    :model,
    :active_requests,
    :session_options,
    :session_id        # Add this - stores current session
  ]
end
```

#### 2. Automatic Session Resumption
When building CLI commands, automatically use `--resume` if we have a session_id:
```elixir
defp build_args(prompt, opts, session_id) do
  base_args = @required_flags

  # Automatically resume session if we have one
  resume_args = if session_id do
    ["--resume", session_id]
  else
    []
  end

  option_args = Options.to_cli_args(opts)
  base_args ++ resume_args ++ option_args ++ [prompt]
end
```

#### 3. Capture and Store Session IDs
Update the session ID whenever we receive it:
```elixir
def handle_info({port, {:data, line}}, state) do
  case Message.parse(line) do
    {:ok, %Message.System{session_id: session_id}} when not is_nil(session_id) ->
      new_state = %{state | session_id: session_id}
      # ... continue processing
  end
end
```

#### 4. Public API for Session Management
```elixir
# Clear the current session (start fresh)
@spec clear(name :: atom() | pid()) :: :ok
def clear(session) do
  GenServer.call(session, :clear_session)
end

# Get current session ID (for debugging/logging)
@spec get_session_id(name :: atom() | pid()) :: {:ok, String.t() | nil}
def get_session_id(session) do
  GenServer.call(session, :get_session_id)
end
```

### Benefits of This Approach

1. **Intuitive Behavior** - Conversations naturally continue, matching user expectations
2. **Zero Configuration** - Works automatically without any user setup
3. **Explicit Control** - Users can clear sessions when they want a fresh start
4. **Stateful by Default** - Leverages the GenServer's natural state management
5. **No Breaking Changes** - Existing API remains the same, just becomes smarter

### Example Usage

```elixir
# Start a session
{:ok, session} = ClaudeCode.start_session(api_key: "...")

# First query starts a new conversation
{:ok, "Hello! I can help..."} = ClaudeCode.query(session, "Hello")

# Subsequent queries continue the conversation automatically
{:ok, "As I mentioned earlier..."} = ClaudeCode.query(session, "What did you say?")

# Clear to start fresh
:ok = ClaudeCode.clear(session)

# Next query starts a new conversation
{:ok, "Hello! How can I help?"} = ClaudeCode.query(session, "Hi")
```

### Implementation Notes

- Session IDs persist for the lifetime of the GenServer process
- If the CLI returns an error for an invalid session ID, we should clear it and retry
- Consider adding session ID to logs for debugging
- No need for `:continue` or `:resume` user options - this is all internal
