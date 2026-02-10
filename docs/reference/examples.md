# Examples

Code patterns and recipes for common ClaudeCode use cases.

For specific topics, see the dedicated guides:
- [Streaming Output](../guides/streaming-output.md) - Real-time response streaming
- [Sessions](../guides/sessions.md) - Multi-turn conversations
- [Phoenix](../integration/phoenix.md) - LiveView and controller integration
- [MCP](../integration/mcp.md) - Custom tools with Hermes MCP
- [Tool Callbacks](../integration/tool-callbacks.md) - Monitoring and auditing

## CLI Applications

### Interactive Code Assistant

```elixir
defmodule CodeAssistant do
  def main(args) do
    case setup_session() do
      {:ok, session} ->
        run_loop(session, args)
        ClaudeCode.stop(session)

      {:error, reason} ->
        IO.puts("Failed to start: #{reason}")
        System.halt(1)
    end
  end

  defp setup_session do
    ClaudeCode.start_link(
      system_prompt: "You are an expert Elixir developer.",
      allowed_tools: ["View", "Edit", "Bash(git:*)"],
      timeout: 300_000
    )
  end

  defp run_loop(session, []) do
    IO.puts("Code Assistant Ready! (type 'quit' to exit)")
    interactive_loop(session)
  end

  defp run_loop(session, args) do
    prompt = Enum.join(args, " ")

    session
    |> ClaudeCode.stream(prompt)
    |> ClaudeCode.Stream.text_content()
    |> Enum.each(&IO.write/1)

    IO.puts("\n")
  end

  defp interactive_loop(session) do
    case IO.gets("> ") |> String.trim() do
      "quit" -> IO.puts("Goodbye!")
      "" -> interactive_loop(session)
      prompt ->
        session
        |> ClaudeCode.stream(prompt)
        |> ClaudeCode.Stream.text_content()
        |> Enum.each(&IO.write/1)

        IO.puts("\n")
        interactive_loop(session)
    end
  end
end
```

## Batch Processing

### File Analysis Pipeline

Analyze multiple files with concurrent processing:

```elixir
defmodule FileAnalyzer do
  def analyze_directory(path, pattern \\ "**/*.ex") do
    files = Path.wildcard(Path.join(path, pattern))
    session_count = min(System.schedulers_online(), 4)
    sessions = start_sessions(session_count)

    try do
      files
      |> Task.async_stream(
           fn file -> analyze_file(sessions, file) end,
           max_concurrency: session_count,
           timeout: 300_000
         )
      |> Enum.map(fn {:ok, result} -> result end)
    after
      stop_sessions(sessions)
    end
  end

  defp start_sessions(count) do
    Enum.map(1..count, fn _ ->
      {:ok, session} = ClaudeCode.start_link(
        system_prompt: "Analyze Elixir code for quality and issues.",
        allowed_tools: ["View"],
        timeout: 180_000
      )
      session
    end)
  end

  defp stop_sessions(sessions) do
    Enum.each(sessions, &ClaudeCode.stop/1)
  end

  defp analyze_file(sessions, file_path) do
    session = Enum.at(sessions, :erlang.phash2(file_path, length(sessions)))

    try do
      analysis =
        session
        |> ClaudeCode.stream("Analyze: #{file_path}")
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      %{file: file_path, analysis: analysis, analyzed_at: DateTime.utc_now()}
    catch
      error -> %{file: file_path, error: error, analyzed_at: DateTime.utc_now()}
    end
  end
end
```

## Code Analysis Tools

### Dependency Analyzer

```elixir
defmodule DependencyAnalyzer do
  def analyze_mix_file(project_path \\ ".") do
    mix_file = Path.join(project_path, "mix.exs")
    lock_file = Path.join(project_path, "mix.lock")

    {:ok, session} = ClaudeCode.start_link(
      system_prompt: "You are an Elixir dependency expert.",
      allowed_tools: ["View"]
    )

    prompt = """
    Analyze the dependencies in #{mix_file} and #{lock_file}.
    Check for security vulnerabilities, outdated versions, and conflicts.
    """

    try do
      analysis =
        session
        |> ClaudeCode.stream(prompt)
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      {:ok, analysis}
    after
      ClaudeCode.stop(session)
    end
  end
end
```

### Test Generator

```elixir
defmodule TestGenerator do
  def generate_tests_for_module(module_file) do
    {:ok, session} = ClaudeCode.start_link(
      system_prompt: """
      You are an Elixir testing expert.
      Generate comprehensive ExUnit tests including happy paths,
      edge cases, and error conditions.
      """,
      allowed_tools: ["View", "Edit"],
      timeout: 300_000
    )

    prompt = "Generate tests for: #{module_file}"

    result =
      session
      |> ClaudeCode.stream(prompt)
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()

    ClaudeCode.stop(session)
    {:ok, result}
  end
end
```

## Error Recovery

### Retry with Backoff

```elixir
defmodule ResilientQuery do
  def query_with_retry(session, prompt, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay = Keyword.get(opts, :base_delay_ms, 1000)

    do_query(session, prompt, opts, max_retries, base_delay, 0)
  end

  defp do_query(session, prompt, opts, max_retries, base_delay, attempt) do
    try do
      result =
        session
        |> ClaudeCode.stream(prompt, opts)
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      {:ok, result}
    catch
      error when attempt < max_retries ->
        delay = base_delay * :math.pow(2, attempt)
        :timer.sleep(round(delay))
        do_query(session, prompt, opts, max_retries, base_delay, attempt + 1)

      error ->
        {:error, {error, attempts: attempt + 1}}
    end
  end
end
```

### Circuit Breaker Pattern

```elixir
defmodule ClaudeCircuitBreaker do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def query(prompt) do
    GenServer.call(__MODULE__, {:query, prompt}, 60_000)
  end

  def init(opts) do
    {:ok, session} = ClaudeCode.start_link(opts)
    {:ok, %{session: session, failures: 0, state: :closed}}
  end

  def handle_call({:query, _prompt}, _from, %{state: :open} = state) do
    {:reply, {:error, :circuit_open}, state}
  end

  def handle_call({:query, prompt}, _from, %{session: session} = state) do
    try do
      response =
        session
        |> ClaudeCode.stream(prompt)
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      {:reply, {:ok, response}, %{state | failures: 0, state: :closed}}
    catch
      error ->
        new_failures = state.failures + 1
        new_state = if new_failures >= 3, do: :open, else: :closed

        if new_state == :open do
          Process.send_after(self(), :half_open, 30_000)
        end

        {:reply, {:error, error}, %{state | failures: new_failures, state: new_state}}
    end
  end

  def handle_info(:half_open, state) do
    {:noreply, %{state | state: :half_open, failures: 0}}
  end
end
```

## Telemetry Integration

```elixir
defmodule ClaudeMetrics do
  def stream_with_metrics(session, prompt, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result =
        session
        |> ClaudeCode.stream(prompt, opts)
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      duration = System.monotonic_time(:millisecond) - start_time

      :telemetry.execute(
        [:claude_code, :query],
        %{duration_ms: duration},
        %{success: true}
      )

      {:ok, result}
    catch
      error ->
        duration = System.monotonic_time(:millisecond) - start_time

        :telemetry.execute(
          [:claude_code, :query],
          %{duration_ms: duration},
          %{success: false}
        )

        {:error, error}
    end
  end
end

# Attach handler
:telemetry.attach(
  "claude-logger",
  [:claude_code, :query],
  fn _event, %{duration_ms: duration}, %{success: success}, _config ->
    IO.puts("Query took #{duration}ms, success: #{success}")
  end,
  nil
)
```

## Next Steps

- [Quickstart](../guides/quickstart.md) - Installation and setup
- `ClaudeCode.Options` - All options and precedence rules
- [Troubleshooting](troubleshooting.md) - Common issues
