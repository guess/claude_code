# Examples

This document provides real-world examples of using ClaudeCode in different scenarios.

## Table of Contents

- [CLI Applications](#cli-applications)
- [Web Applications](#web-applications)
- [Phoenix LiveView Integration](#phoenix-liveview-integration)
- [Batch Processing](#batch-processing)
- [Code Analysis Tools](#code-analysis-tools)
- [Testing Applications](#testing-applications)

## CLI Applications

### Interactive Code Assistant

Build a CLI tool that helps with coding tasks:

```elixir
# lib/code_assistant.ex
defmodule CodeAssistant do
  @moduledoc """
  Interactive CLI tool for code assistance using ClaudeCode.
  """

  def main(args) do
    case setup_session() do
      {:ok, session} ->
        run_interactive_loop(session, args)
        ClaudeCode.stop(session)

      {:error, reason} ->
        IO.puts("Failed to start: #{reason}")
        System.halt(1)
    end
  end

  defp setup_session do
    ClaudeCode.start_link(
      system_prompt: """
      You are an expert Elixir developer assistant. Help with:
      - Code review and suggestions
      - Debugging issues
      - Writing tests
      - Performance optimization
      - Best practices
      """,
      allowed_tools: ["View", "Edit", "Bash(git:*)"],
      timeout: 300_000
    )
  end

  defp run_interactive_loop(session, []) do
    IO.puts("🚀 Code Assistant Ready! (type 'quit' to exit)")
    interactive_loop(session)
  end

  defp run_interactive_loop(session, args) do
    # Non-interactive mode - process arguments as single query
    prompt = Enum.join(args, " ")

    session
    |> ClaudeCode.query_stream(prompt)
    |> ClaudeCode.Stream.text_content()
    |> Enum.each(&IO.write/1)

    IO.puts("\n")
  end

  defp interactive_loop(session) do
    case IO.gets("code_assistant> ") |> String.trim() do
      "quit" ->
        IO.puts("Goodbye! 👋")

      "" ->
        interactive_loop(session)

      prompt ->
        handle_query(session, prompt)
        interactive_loop(session)
    end
  end

  defp handle_query(session, prompt) do
    session
    |> ClaudeCode.query_stream(prompt)
    |> ClaudeCode.Stream.text_content()
    |> Enum.each(&IO.write/1)

    IO.puts("\n")
  rescue
    error ->
      IO.puts("Error: #{inspect(error)}")
  end
end
```

Usage:
```bash
# Interactive mode
mix run -e "CodeAssistant.main([])"

# Single query mode
mix run -e "CodeAssistant.main(['Review', 'this', 'function'])"
```

## Web Applications

### Claude Service for Phoenix Apps

Integrate ClaudeCode into a Phoenix application:

```elixir
# lib/my_app/claude_service.ex
defmodule MyApp.ClaudeService do
  @moduledoc """
  Service for managing Claude interactions in a Phoenix application.
  """
  use GenServer
  require Logger

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ask(prompt, options \\ []) do
    GenServer.call(__MODULE__, {:ask, prompt, options}, 30_000)
  end

  def ask_async(prompt, options \\ []) do
    GenServer.cast(__MODULE__, {:ask_async, prompt, options, self()})
  end

  def stream_query(prompt, options \\ []) do
    GenServer.call(__MODULE__, {:stream, prompt, options})
  end

  # Server Implementation
  def init(opts) do
    case start_claude_session(opts) do
      {:ok, session} ->
        Logger.info("ClaudeService started successfully")
        {:ok, %{session: session, active_streams: %{}}}

      {:error, reason} ->
        Logger.error("Failed to start ClaudeService: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def handle_call({:ask, prompt, options}, _from, %{session: session} = state) do
    case ClaudeCode.query(session, prompt, options) do
      {:ok, response} ->
        {:reply, {:ok, response}, state}

      {:error, reason} ->
        Logger.warning("Claude query failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stream, prompt, options}, {pid, _ref}, %{session: session} = state) do
    try do
      stream = ClaudeCode.query_stream(session, prompt, options)
      stream_id = make_ref()

      # Store the stream for cleanup
      new_state = put_in(state.active_streams[stream_id], {pid, stream})

      {:reply, {:ok, stream_id, stream}, new_state}
    rescue
      error ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_cast({:ask_async, prompt, options, caller_pid}, %{session: session} = state) do
    Task.start(fn ->
      case ClaudeCode.query(session, prompt, options) do
        {:ok, response} ->
          send(caller_pid, {:claude_response, {:ok, response}})

        {:error, reason} ->
          send(caller_pid, {:claude_response, {:error, reason}})
      end
    end)

    {:noreply, state}
  end

  # Cleanup completed streams
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_streams = state.active_streams
                  |> Enum.reject(fn {_id, {stream_pid, _stream}} -> stream_pid == pid end)
                  |> Map.new()

    {:noreply, %{state | active_streams: new_streams}}
  end

  defp start_claude_session(opts) do
    claude_opts = [
      system_prompt: "You are a helpful assistant for a web application",
      allowed_tools: ["View"],
      timeout: 180_000
    ] ++ opts

    ClaudeCode.start_link(claude_opts)
  end
end
```

### Phoenix Controller Integration

```elixir
# lib/my_app_web/controllers/claude_controller.ex
defmodule MyAppWeb.ClaudeController do
  use MyAppWeb, :controller
  alias MyApp.ClaudeService

  def ask(conn, %{"prompt" => prompt}) do
    case ClaudeService.ask(prompt) do
      {:ok, response} ->
        json(conn, %{response: response})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  def stream(conn, %{"prompt" => prompt}) do
    case ClaudeService.stream_query(prompt) do
      {:ok, _stream_id, stream} ->
        conn = put_resp_header(conn, "content-type", "text/plain")
        conn = send_chunked(conn, 200)

        stream
        |> ClaudeCode.Stream.text_content()
        |> Enum.reduce_while(conn, fn chunk, conn ->
          case chunk(conn, chunk) do
            {:ok, conn} -> {:cont, conn}
            {:error, :closed} -> {:halt, conn}
          end
        end)

        conn

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end
end
```

## Phoenix LiveView Integration

### Real-time Chat Interface

```elixir
# lib/my_app_web/live/claude_chat_live.ex
defmodule MyAppWeb.ClaudeChatLive do
  use MyAppWeb, :live_view
  alias MyApp.ClaudeService

  def mount(_params, _session, socket) do
    socket = assign(socket,
      messages: [],
      current_input: "",
      loading: false,
      stream_content: "",
      stream_active: false
    )

    {:ok, socket}
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" do
      # Add user message
      socket = add_message(socket, "user", message)
      socket = assign(socket, current_input: "", loading: true, stream_active: true)

      # Start streaming Claude's response
      case ClaudeService.stream_query(message) do
        {:ok, _stream_id, stream} ->
          start_streaming(stream)
          {:noreply, socket}

        {:error, reason} ->
          socket = add_message(socket, "error", "Error: #{inspect(reason)}")
          socket = assign(socket, loading: false, stream_active: false)
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, current_input: message)}
  end

  def handle_info({:stream_chunk, chunk}, socket) do
    socket = assign(socket, stream_content: socket.assigns.stream_content <> chunk)
    {:noreply, socket}
  end

  def handle_info(:stream_complete, socket) do
    # Add the complete streamed response as a message
    socket = add_message(socket, "claude", socket.assigns.stream_content)
    socket = assign(socket,
      loading: false,
      stream_active: false,
      stream_content: ""
    )
    {:noreply, socket}
  end

  def handle_info(:stream_error, socket) do
    socket = add_message(socket, "error", "Stream error occurred")
    socket = assign(socket, loading: false, stream_active: false, stream_content: "")
    {:noreply, socket}
  end

  defp start_streaming(stream) do
    parent = self()

    Task.start(fn ->
      try do
        stream
        |> ClaudeCode.Stream.text_content()
        |> Enum.each(fn chunk ->
          send(parent, {:stream_chunk, chunk})
        end)

        send(parent, :stream_complete)
      rescue
        _error ->
          send(parent, :stream_error)
      end
    end)
  end

  defp add_message(socket, role, content) do
    message = %{role: role, content: content, timestamp: DateTime.utc_now()}
    assign(socket, messages: socket.assigns.messages ++ [message])
  end

  def render(assigns) do
    ~H"""
    <div class="claude-chat">
      <div class="messages" id="messages" phx-update="ignore">
        <%= for message <- @messages do %>
          <div class={"message message-#{message.role}"}>
            <strong><%= String.capitalize(message.role) %>:</strong>
            <span><%= message.content %></span>
          </div>
        <% end %>

        <%= if @stream_active and @stream_content != "" do %>
          <div class="message message-claude streaming">
            <strong>Claude:</strong>
            <span><%= @stream_content %></span>
            <span class="cursor">▊</span>
          </div>
        <% end %>
      </div>

      <form phx-submit="send_message" class="input-form">
        <input
          type="text"
          name="message"
          value={@current_input}
          phx-change="update_input"
          placeholder="Ask Claude something..."
          disabled={@loading}
          autocomplete="off"
        />
        <button type="submit" disabled={@loading}>
          <%= if @loading, do: "...", else: "Send" %>
        </button>
      </form>
    </div>
    """
  end
end
```

## Batch Processing

### File Analysis Pipeline

```elixir
# lib/file_analyzer.ex
defmodule FileAnalyzer do
  @moduledoc """
  Analyze multiple files using ClaudeCode with concurrent processing.
  """

  def analyze_directory(path, pattern \\ "**/*.ex") do
    files = Path.wildcard(Path.join(path, pattern))

    # Start multiple Claude sessions for parallel processing
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
    1..count
    |> Enum.map(fn _i ->
      {:ok, session} = ClaudeCode.start_link(
        system_prompt: """
        You are a code analysis expert. Analyze Elixir files and provide:
        1. Code quality assessment
        2. Potential improvements
        3. Bug detection
        4. Performance suggestions
        """,
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
    # Round-robin session selection
    session_index = :erlang.phash2(file_path, length(sessions))
    session = Enum.at(sessions, session_index)

    prompt = """
    Please analyze this Elixir file: #{file_path}

    Provide a concise analysis including:
    - Overall code quality (1-10)
    - Key issues found
    - Improvement suggestions
    - Estimated complexity
    """

    case ClaudeCode.query(session, prompt) do
      {:ok, analysis} ->
        %{
          file: file_path,
          analysis: analysis,
          analyzed_at: DateTime.utc_now()
        }

      {:error, reason} ->
        %{
          file: file_path,
          error: reason,
          analyzed_at: DateTime.utc_now()
        }
    end
  end

  def generate_report(results) do
    successful = Enum.filter(results, &Map.has_key?(&1, :analysis))
    failed = Enum.filter(results, &Map.has_key?(&1, :error))

    """
    # Code Analysis Report

    **Files Analyzed:** #{length(results)}
    **Successful:** #{length(successful)}
    **Failed:** #{length(failed)}
    **Generated:** #{DateTime.utc_now()}

    ## Analysis Results

    #{Enum.map_join(successful, "\n\n", &format_analysis/1)}

    #{if length(failed) > 0 do
      """
      ## Failed Analyses

      #{Enum.map_join(failed, "\n", &"- #{&1.file}: #{inspect(&1.error)}")}
      """
    else
      ""
    end}
    """
  end

  defp format_analysis(result) do
    """
    ### #{result.file}

    #{result.analysis}
    """
  end
end

# Usage:
# results = FileAnalyzer.analyze_directory("lib/")
# report = FileAnalyzer.generate_report(results)
# File.write!("analysis_report.md", report)
```

## Code Analysis Tools

### Dependency Analyzer

```elixir
# lib/dependency_analyzer.ex
defmodule DependencyAnalyzer do
  @moduledoc """
  Analyze project dependencies using ClaudeCode.
  """

  def analyze_mix_file(project_path \\ ".") do
    mix_file = Path.join(project_path, "mix.exs")
    lock_file = Path.join(project_path, "mix.lock")

    {:ok, session} = ClaudeCode.start_link(
      system_prompt: """
      You are an Elixir dependency expert. Analyze mix.exs and mix.lock files to provide:
      1. Dependency security assessment
      2. Version recommendations
      3. Potential conflicts
      4. Unused dependencies
      5. Performance impact
      """,
      allowed_tools: ["View"]
    )

    prompt = """
    Please analyze the dependencies in this Elixir project.

    Look at both mix.exs and mix.lock files and provide:
    - Security vulnerabilities
    - Outdated dependencies
    - Dependency conflicts
    - Recommendations for optimization

    Files to analyze:
    - #{mix_file}
    - #{lock_file}
    """

    case ClaudeCode.query(session, prompt) do
      {:ok, analysis} ->
        ClaudeCode.stop(session)
        {:ok, analysis}

      error ->
        ClaudeCode.stop(session)
        error
    end
  end

  def compare_with_alternatives(dependency_name) do
    {:ok, session} = ClaudeCode.start_link(
      system_prompt: "You are an Elixir ecosystem expert.",
      timeout: 120_000
    )

    prompt = """
    Compare the Elixir dependency "#{dependency_name}" with its alternatives.

    Provide:
    1. Popular alternatives
    2. Pros/cons comparison
    3. Migration difficulty
    4. Performance differences
    5. Community adoption
    """

    case ClaudeCode.query(session, prompt) do
      {:ok, comparison} ->
        ClaudeCode.stop(session)
        {:ok, comparison}

      error ->
        ClaudeCode.stop(session)
        error
    end
  end
end
```

## Testing Applications

### Test Generator

```elixir
# lib/test_generator.ex
defmodule TestGenerator do
  @moduledoc """
  Generate tests for Elixir modules using ClaudeCode.
  """

  def generate_tests_for_module(module_file) do
    {:ok, session} = ClaudeCode.start_link(
      system_prompt: """
      You are an Elixir testing expert. Generate comprehensive ExUnit tests including:
      1. Happy path tests
      2. Edge case tests
      3. Error condition tests
      4. Property-based tests when appropriate
      5. Mock usage when needed
      """,
      allowed_tools: ["View", "Edit"],
      timeout: 300_000
    )

    prompt = """
    Please generate comprehensive ExUnit tests for the module in: #{module_file}

    Create a complete test file that covers:
    - All public functions
    - Edge cases and error conditions
    - Property-based tests where appropriate
    - Proper setup and teardown

    Follow Elixir testing best practices and use descriptive test names.
    """

    session
    |> ClaudeCode.query_stream(prompt)
    |> ClaudeCode.Stream.text_content()
    |> Enum.to_list()
    |> Enum.join()
    |> then(fn test_content ->
      ClaudeCode.stop(session)
      {:ok, test_content}
    end)
  rescue
    error ->
      ClaudeCode.stop(session)
      {:error, error}
  end

  def improve_existing_tests(test_file) do
    {:ok, session} = ClaudeCode.start_link(
      system_prompt: """
      You are an Elixir testing expert. Improve existing test files by:
      1. Adding missing test cases
      2. Improving test descriptions
      3. Adding property-based tests
      4. Optimizing test structure
      5. Adding better assertions
      """,
      allowed_tools: ["View", "Edit"]
    )

    prompt = """
    Please analyze and improve the test file: #{test_file}

    Suggest improvements for:
    - Test coverage gaps
    - Better test organization
    - More descriptive test names
    - Additional edge cases
    - Performance test optimizations
    """

    case ClaudeCode.query(session, prompt) do
      {:ok, suggestions} ->
        ClaudeCode.stop(session)
        {:ok, suggestions}

      error ->
        ClaudeCode.stop(session)
        error
    end
  end
end

# Usage:
# {:ok, tests} = TestGenerator.generate_tests_for_module("lib/my_module.ex")
# File.write!("test/my_module_test.exs", tests)
```

## Performance Monitoring

### Stream Performance Monitor

```elixir
# lib/performance_monitor.ex
defmodule PerformanceMonitor do
  @moduledoc """
  Monitor ClaudeCode performance and stream metrics.
  """

  def monitor_stream_performance(session, prompt) do
    start_time = System.monotonic_time(:millisecond)

    metrics = %{
      start_time: start_time,
      first_chunk_time: nil,
      total_chunks: 0,
      total_characters: 0,
      end_time: nil
    }

    session
    |> ClaudeCode.query_stream(prompt)
    |> ClaudeCode.Stream.text_content()
    |> Stream.with_index()
    |> Stream.map(fn {chunk, index} ->
      current_time = System.monotonic_time(:millisecond)

      metrics = if index == 0 do
        %{metrics | first_chunk_time: current_time}
      else
        metrics
      end

      metrics = %{metrics |
        total_chunks: index + 1,
        total_characters: metrics.total_characters + String.length(chunk),
        end_time: current_time
      }

      {chunk, metrics}
    end)
    |> Enum.reduce({[], nil}, fn {chunk, metrics}, {chunks, _} ->
      {[chunk | chunks], metrics}
    end)
    |> case do
      {chunks, final_metrics} ->
        content = chunks |> Enum.reverse() |> Enum.join()

        report = generate_performance_report(final_metrics)

        {:ok, content, report}
    end
  end

  defp generate_performance_report(metrics) do
    %{
      total_duration_ms: metrics.end_time - metrics.start_time,
      time_to_first_chunk_ms: metrics.first_chunk_time - metrics.start_time,
      total_chunks: metrics.total_chunks,
      total_characters: metrics.total_characters,
      characters_per_second: metrics.total_characters /
        ((metrics.end_time - metrics.start_time) / 1000),
      chunks_per_second: metrics.total_chunks /
        ((metrics.end_time - metrics.start_time) / 1000)
    }
  end
end

# Usage:
# {:ok, session} = ClaudeCode.start_link(api_key: "...")
# {:ok, content, report} = PerformanceMonitor.monitor_stream_performance(
#   session, "Write a long explanation of GenServers"
# )
# IO.inspect(report)
```

## Error Recovery Patterns

### Resilient Query Handler

```elixir
defmodule ResilientClaudeHandler do
  @moduledoc """
  Handle Claude queries with automatic retry and error recovery.
  """

  def query_with_retry(session, prompt, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay = Keyword.get(opts, :base_delay_ms, 1000)

    do_query_with_retry(session, prompt, opts, max_retries, base_delay, 0)
  end

  defp do_query_with_retry(session, prompt, opts, max_retries, base_delay, attempt) do
    case ClaudeCode.query(session, prompt, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, :timeout} when attempt < max_retries ->
        delay = base_delay * :math.pow(2, attempt)
        :timer.sleep(round(delay))
        do_query_with_retry(session, prompt, opts, max_retries, base_delay, attempt + 1)

      {:error, {:cli_exit, _}} when attempt < max_retries ->
        # CLI crashed, might recover on retry
        delay = base_delay * :math.pow(2, attempt)
        :timer.sleep(round(delay))
        do_query_with_retry(session, prompt, opts, max_retries, base_delay, attempt + 1)

      error ->
        {:error, {error, attempts: attempt + 1}}
    end
  end

  def stream_with_recovery(session, prompt, opts \\ []) do
    try do
      session
      |> ClaudeCode.query_stream(prompt, opts)
      |> ClaudeCode.Stream.text_content()
      |> Stream.map(&{:ok, &1})
    rescue
      error ->
        Stream.once({:error, error})
    end
  end
end
```

These examples demonstrate various real-world usage patterns for ClaudeCode, from simple CLI tools to complex web applications with streaming interfaces. Each example includes proper error handling and follows Elixir best practices.
