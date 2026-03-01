# Troubleshooting

This guide helps you diagnose and resolve common issues with the ClaudeCode Elixir SDK.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Authentication Problems](#authentication-problems)
- [CLI Integration Issues](#cli-integration-issues)
- [Session Management](#session-management)
- [Streaming Problems](#streaming-problems)
- [Performance Issues](#performance-issues)
- [Error Reference](#error-reference)

## Installation Issues

### ClaudeCode Package Not Found

**Problem:** `mix deps.get` fails to find the ClaudeCode package.

**Solution:**
```elixir
# Make sure you're using the correct package name and version
def deps do
  [
    {:claude_code, "~> 0.27"}
  ]
end
```

If using a pre-release version:
```elixir
def deps do
  [
    {:claude_code, github: "guess/claude_code", branch: "main"}
  ]
end
```

### Compilation Errors

**Problem:** ClaudeCode fails to compile with dependency errors.

**Common causes:**
- Incompatible Elixir/OTP versions
- Missing required dependencies

**Solution:**
```bash
# Check your Elixir version (requires 1.18+)
elixir --version

# Clean and reinstall dependencies
mix deps.clean --all
mix deps.get
mix compile
```

## Authentication Problems

### Invalid API Key Error

**Problem:** Getting authentication errors when starting a session.

**Error message:**
```
{:error, {:claude_error, "Authentication failed"}}
```

**Solutions:**

1. **Check your API key:**
   ```bash
   echo $ANTHROPIC_API_KEY
   ```

2. **Verify the key format:**
   ```bash
   # Should start with 'sk-ant-'
   export ANTHROPIC_API_KEY="sk-ant-your-key-here"
   ```

3. **Test with the Claude CLI directly:**
   ```bash
   claude --version
   echo "Hello" | claude
   ```

4. **Use a different environment variable:**
   ```elixir
   {:ok, session} = ClaudeCode.start_link(
     api_key: System.get_env("MY_CLAUDE_KEY")
   )
   ```

### API Key Not Found

**Problem:** Session fails to start with missing API key.

**Error message:**
```
{:error, "API key is required"}
```

**Solutions:**

1. **Set the environment variable:**
   ```bash
   export ANTHROPIC_API_KEY="your-key-here"
   ```

2. **Pass the key directly:**
   ```elixir
   {:ok, session} = ClaudeCode.start_link(
     api_key: "your-key-here"  # Not recommended for production
   )
   ```

3. **Use application config:**
   ```elixir
   # config/config.exs
   config :claude_code,
     api_key: System.get_env("ANTHROPIC_API_KEY")
   ```

## CLI Integration Issues

### Claude CLI Not Found

**Problem:** ClaudeCode can't find the Claude CLI binary.

**Error message:**
```
{:error, {:cli_not_found, "Claude CLI not found."}}
```

**Solutions:**

1. **Use the default bundled mode** (auto-installs to priv/bin/):
   ```bash
   mix claude_code.install
   ```
   With the default `cli_path: :bundled`, the SDK auto-installs the CLI on first use.
   If auto-install fails (e.g., no network), pre-install with the mix task.

2. **Use a global installation:**
   ```bash
   # Install the CLI system-wide
   curl -fsSL https://claude.ai/install.sh | bash

   # Then configure the SDK to use it
   config :claude_code, cli_path: :global
   ```

3. **Use an explicit path:**
   ```elixir
   config :claude_code, cli_path: "/path/to/claude"
   ```

4. **Check the resolved path:**
   ```bash
   mix claude_code.path
   ```

### CLI Version Compatibility

**Problem:** ClaudeCode doesn't work with your Claude CLI version.

**Solution:**
```bash
# Check CLI version
claude --version

# Update to latest version
# Follow update instructions at claude.ai/code
```

Supported CLI versions: 0.8.0+

### CLI Hangs or Times Out

**Problem:** CLI subprocess hangs or doesn't respond.

**Common causes:**
- CLI waiting for input
- Network connectivity issues
- CLI process stuck

**Solutions:**

1. **Check timeout settings:**
   ```elixir
   {:ok, session} = ClaudeCode.start_link(
     api_key: "...",
     timeout: 300_000  # 5 minutes
   )
   ```

2. **Test CLI directly:**
   ```bash
   echo "Hello" | claude --print
   ```

3. **Check network connectivity:**
   ```bash
   curl -I https://api.anthropic.com
   ```

## Session Management

### Session Dies Unexpectedly

**Problem:** Session GenServer crashes or stops responding.

**Debugging steps:**

1. **Check session status:**
   ```elixir
   ClaudeCode.alive?(session)
   ```

2. **Use supervision (manual setup required):**
   ```elixir
   # ClaudeCode doesn't provide built-in child_spec
   # You need to create a wrapper or use a simple supervisor
   defmodule MyApp.ClaudeSupervisor do
     use Supervisor

     def start_link(opts) do
       Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
     end

     def init(opts) do
       children = [
         {ClaudeCode, [api_key: "...", name: :claude_session]}
       ]

       Supervisor.init(children, strategy: :one_for_one)
     end
   end
   ```

### Session State Corruption

**Problem:** Session maintains incorrect conversation context.

**Solutions:**

1. **Clear session state:**
   ```elixir
   ClaudeCode.clear(session)
   ```

2. **Restart session:**
   ```elixir
   ClaudeCode.stop(session)
   {:ok, new_session} = ClaudeCode.start_link(opts)
   ```

3. **Use fresh sessions for unrelated queries:**
   ```elixir
   # For isolated queries, use the one-off query/2
   {:ok, result} = ClaudeCode.query(prompt)

   # Or manually manage a session
   {:ok, temp_session} = ClaudeCode.start_link()
   temp_session |> ClaudeCode.stream(prompt) |> Stream.run()
   ClaudeCode.stop(temp_session)
   ```

## Streaming Problems

### Stream Doesn't Start

**Problem:** Streaming query returns empty stream or never yields data.

**Debugging:**

1. **Test with one-off query first:**
   ```elixir
   case ClaudeCode.query(prompt) do
     {:ok, response} -> IO.puts("One-off works: #{response}")
     error -> IO.puts("One-off error: #{inspect(error)}")
   end
   ```

2. **Check stream consumption:**
   ```elixir
   # Force stream evaluation
   session
   |> ClaudeCode.stream(prompt)
   |> Enum.to_list()
   |> IO.inspect()
   ```

3. **Use stream utilities:**
   ```elixir
   session
   |> ClaudeCode.stream(prompt)
   |> ClaudeCode.Stream.text_content()
   |> Enum.each(&IO.write/1)
   ```

### Stream Hangs or Stalls

**Problem:** Stream starts but stops producing data.

**Solutions:**

1. **Add timeouts:**
   ```elixir
   session
   |> ClaudeCode.stream(prompt, timeout: 120_000)
   |> Stream.take_while(fn _ -> true end)
   |> Enum.to_list()
   ```

2. **Use stream debugging:**
   ```elixir
   session
   |> ClaudeCode.stream(prompt)
   |> Stream.each(fn msg -> IO.inspect(msg, label: "Stream message") end)
   |> ClaudeCode.Stream.text_content()
   |> Enum.to_list()
   ```

### Memory Issues with Large Streams

**Problem:** Streaming large responses causes memory issues.

**Solutions:**

1. **Process chunks immediately:**
   ```elixir
   session
   |> ClaudeCode.stream(prompt)
   |> ClaudeCode.Stream.text_content()
   |> Stream.each(&IO.write/1)  # Don't accumulate
   |> Stream.run()
   ```

2. **Use collect for structured results:**
   ```elixir
   # When you need the full response organized
   summary = session
   |> ClaudeCode.stream(prompt)
   |> ClaudeCode.Stream.collect()

   # Process the collected data
   IO.puts(summary.result)
   ```

## Performance Issues

### Slow Query Response

**Problem:** Queries take too long to respond.

**Optimization strategies:**

1. **Use appropriate models:**
   ```elixir
   # For simple tasks, use faster models
   {:ok, session} = ClaudeCode.start_link(
     api_key: "...",
     model: "claude-3-haiku-20240307"  # Faster model
   )
   ```

2. **Optimize prompts:**
   ```elixir
   # Be specific and concise
   prompt = "Briefly explain GenServers in 2 paragraphs."
   ```

3. **Use streaming for responsiveness:**
   ```elixir
   # User sees response immediately
   session
   |> ClaudeCode.stream(prompt)
   |> ClaudeCode.Stream.text_content()
   |> Enum.each(&IO.write/1)
   ```

### High Memory Usage

**Problem:** ClaudeCode uses too much memory.

**Solutions:**

1. **Limit concurrent sessions:**
   ```elixir
   # Limit the number of concurrent sessions manually
   # (No built-in session pooling - you need to implement this)
   max_sessions = System.schedulers_online()
   # Example: Use Task.async_stream with max_concurrency
   ```

2. **Clean up sessions:**
   ```elixir
   # Always stop sessions when done
   ClaudeCode.stop(session)
   ```

3. **Monitor memory usage:**
   ```elixir
   :erlang.memory()
   ```

### Connection Limits

**Problem:** Too many concurrent requests to Claude API.

**Error message:**
```
{:error, {:claude_error, "Rate limit exceeded"}}
```

**Solutions:**

1. **Implement backoff:**
   ```elixir
   defp query_with_backoff(session, prompt, retries \\ 3) do
     try do
       result =
         session
         |> ClaudeCode.stream(prompt)
         |> ClaudeCode.Stream.text_content()
         |> Enum.join()
       {:ok, result}
     catch
       error when retries > 0 ->
         :timer.sleep(2000)  # Wait 2 seconds
         query_with_backoff(session, prompt, retries - 1)
       error -> {:error, error}
     end
   end
   ```

2. **Use fewer concurrent sessions:**
   ```elixir
   # Limit parallelism
   Task.async_stream(tasks, &process_task/1, max_concurrency: 2)
   ```

## Error Reference

### Common Error Patterns

#### CLI Errors
```elixir
{:error, {:cli_not_found, message}}     # Claude CLI not installed
{:error, {:cli_exit, exit_code}}        # CLI crashed or failed
{:error, {:port_closed, reason}}        # Communication failure
```

#### Authentication Errors
```elixir
{:error, {:claude_error, "Invalid API key"}}
{:error, {:claude_error, "Authentication failed"}}
{:error, {:claude_error, "Rate limit exceeded"}}
```

#### Session Errors
```elixir
{:error, :timeout}                      # Query timed out
{:error, :session_not_found}            # Session doesn't exist
{:error, {:invalid_options, details}}   # Bad configuration
```

#### Stream Errors
```elixir
{:stream_error, reason}                 # Generic stream error
{:stream_timeout, request_ref}          # Stream timed out
{:stream_init_error, reason}            # Failed to start stream
```

### Debugging Commands

#### Check System Status
```elixir
# Check if Claude CLI is available
System.cmd("which", ["claude"])

# Test CLI directly
System.cmd("claude", ["--version"])

# Check environment
System.get_env("ANTHROPIC_API_KEY")

# Test network connectivity
System.cmd("curl", ["-I", "https://api.anthropic.com"])
```

#### Enable Debug Logging
```elixir
# Add to config/config.exs
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n"

# Or in IEx
Logger.configure(level: :debug)
```

#### Monitor Resource Usage
```elixir
# Memory usage
:erlang.memory()

# Process info
Process.info(session_pid)

# System info
:erlang.system_info(:process_count)
```

## Getting Help

If you're still having issues:

1. **Check the logs** - Enable debug logging to see what's happening
2. **Test components individually** - CLI, network, authentication
3. **Create a minimal reproduction** - Isolate the problem
4. **Check GitHub issues** - Someone might have seen this before
5. **Open an issue** - Include logs, environment details, and reproduction steps

### Minimal Reproduction Template

```elixir
# Paste this into IEx to reproduce the issue
alias ClaudeCode

# Your environment
IO.puts("Elixir: #{System.version()}")
IO.puts("OTP: #{System.otp_release()}")

case System.cmd("claude", ["--version"]) do
  {output, 0} -> IO.puts("Claude CLI: #{String.trim(output)}")
  {error, code} -> IO.puts("Claude CLI error: #{error} (exit: #{code})")
end

# Your code that demonstrates the problem
{:ok, session} = ClaudeCode.start_link(
  api_key: System.get_env("ANTHROPIC_API_KEY")
)

# The failing operation
result =
  session
  |> ClaudeCode.stream("Hello")
  |> Enum.to_list()

IO.inspect(result, label: "Result")

ClaudeCode.stop(session)
```

Include this output when reporting issues for faster resolution.
