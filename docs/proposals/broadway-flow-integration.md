# Broadway/Flow Integration for ClaudeCode Elixir SDK

## Executive Summary

This proposal outlines the implementation of Broadway and Flow integration for the ClaudeCode Elixir SDK. This feature leverages Elixir's strengths in concurrent data processing to enable efficient batch processing of AI workloads without requiring changes to the existing supervisor architecture.

## Motivation

### Why Broadway/Flow Instead of Connection Pooling?

1. **Natural fit for AI workloads** - Most Claude use cases involve processing multiple items (documents, code files, emails, etc.)
2. **No breaking changes** - Works alongside existing architecture without supervisor modifications
3. **Built-in production features** - Rate limiting, backpressure, error handling, and metrics
4. **Immediate value** - Users can process thousands of items efficiently without complex setup

### Target Use Cases

- **Code Analysis**: Analyze entire codebases for security issues, patterns, or refactoring opportunities
- **Document Processing**: Summarize, classify, or extract information from large document sets
- **Data Pipeline Integration**: Add AI capabilities to existing ETL workflows
- **Content Generation**: Generate descriptions, translations, or variations at scale
- **Log Analysis**: Process application logs for insights and anomaly detection

## Design Overview

### Core Components

1. **ClaudeCode.Flow** - High-level Flow helpers for common patterns
2. **ClaudeCode.Broadway** - Broadway producer/processor for advanced pipelines
3. **ClaudeCode.Pipeline** - Pre-built pipeline templates
4. **ClaudeCode.RateLimiter** - Token and request rate limiting

### Architecture

```
User Data Source
    ↓
Flow.from_enumerable/Stream
    ↓
Flow.map/filter/reduce → ClaudeCode.query
    ↓
Rate Limiting & Backpressure
    ↓
Results Collection
```

## Implementation Plan

### Phase 1: Flow Integration (Week 1)

#### 1.1 Basic Flow Module
```elixir
defmodule ClaudeCode.Flow do
  @moduledoc """
  Flow integration for efficient batch processing with Claude.
  """

  @doc """
  Process items through Claude with automatic rate limiting.
  
  ## Examples
  
      # Analyze code files
      Path.wildcard("lib/**/*.ex")
      |> ClaudeCode.Flow.map(:analyzer, fn file ->
        "Find bugs in: #{File.read!(file)}"
      end)
      |> Enum.to_list()
  
  """
  def map(enumerable, session, prompt_fn, opts \\ []) do
    max_concurrency = opts[:max_concurrency] || 10
    
    enumerable
    |> Flow.from_enumerable(max_demand: max_concurrency)
    |> Flow.map(fn item ->
      prompt = build_prompt(prompt_fn, item)
      {item, ClaudeCode.query(session, prompt, opts)}
    end)
  end

  @doc """
  Process items and filter based on Claude's response.
  
  ## Examples
  
      # Find files with security issues
      files
      |> ClaudeCode.Flow.filter_map(:security, fn file ->
        {"Contains SQL injection risk?", File.read!(file)}
      end)
      |> Enum.to_list()
  
  """
  def filter_map(enumerable, session, prompt_fn, opts \\ []) do
    enumerable
    |> map(session, prompt_fn, opts)
    |> Flow.filter(fn {_item, result} ->
      String.contains?(String.downcase(result), ["yes", "true", "found", "detected"])
    end)
    |> Flow.map(fn {item, _result} -> item end)
  end

  @doc """
  Batch process items with rate limiting.
  """
  def batch_process(enumerable, session, prompt_fn, opts \\ []) do
    rate_limit = opts[:rate_limit] || 10  # requests per second
    
    enumerable
    |> Stream.chunk_every(rate_limit)
    |> Stream.flat_map(fn batch ->
      start_time = System.monotonic_time(:millisecond)
      
      results = batch
      |> Flow.from_enumerable()
      |> map(session, prompt_fn, opts)
      |> Enum.to_list()
      
      # Ensure we don't exceed rate limit
      elapsed = System.monotonic_time(:millisecond) - start_time
      if elapsed < 1000, do: Process.sleep(1000 - elapsed)
      
      results
    end)
  end

  defp build_prompt(prompt_fn, item) when is_function(prompt_fn, 1) do
    prompt_fn.(item)
  end
  
  defp build_prompt(template, item) when is_binary(template) do
    template
  end
end
```

#### 1.2 Common Pipeline Templates
```elixir
defmodule ClaudeCode.Pipeline do
  @moduledoc """
  Pre-built pipelines for common AI processing tasks.
  """

  @doc """
  Analyze code repository for various aspects.
  """
  def analyze_codebase(path, analyses \\ [:security, :quality, :documentation]) do
    files = Path.wildcard(Path.join(path, "**/*.{ex,exs,js,py,rb}"))
    
    analyses
    |> Enum.map(fn analysis ->
      Task.async(fn ->
        {analysis, run_analysis(files, analysis)}
      end)
    end)
    |> Task.await_many(300_000)  # 5 minute timeout
    |> Map.new()
  end

  defp run_analysis(files, :security) do
    ClaudeCode.Flow.filter_map(files, :analyzer, fn file ->
      content = File.read!(file)
      """
      Analyze this code for security vulnerabilities:
      - SQL injection
      - XSS vulnerabilities  
      - Authentication bypasses
      - Sensitive data exposure
      
      Code:
      #{content}
      
      Respond with 'FOUND' if vulnerabilities exist, 'SAFE' if not.
      """
    end)
    |> Enum.to_list()
  end

  @doc """
  Process documents in parallel with categorization.
  """
  def categorize_documents(documents, categories) do
    prompt_template = """
    Categorize this document into one of these categories:
    #{Enum.join(categories, ", ")}
    
    Document: %{content}
    
    Respond with only the category name.
    """
    
    documents
    |> ClaudeCode.Flow.map(:classifier, fn doc ->
      String.replace(prompt_template, "%{content}", doc.content)
    end)
    |> Flow.reduce(fn -> %{} end, fn {doc, category}, acc ->
      Map.update(acc, category, [doc], &[doc | &1])
    end)
    |> Enum.to_list()
  end
end
```

### Phase 2: Broadway Integration (Week 2)

#### 2.1 Broadway Producer
```elixir
defmodule ClaudeCode.Broadway do
  use Broadway
  require Logger

  @impl true
  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: opts[:name] || __MODULE__,
      producer: [
        module: opts[:producer],
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: opts[:concurrency] || 10,
          max_demand: opts[:max_demand] || 5
        ]
      ],
      batchers: [
        default: [
          batch_size: opts[:batch_size] || 10,
          batch_timeout: opts[:batch_timeout] || 1_000
        ]
      ],
      context: %{
        session: opts[:session] || :default,
        prompt_fn: opts[:prompt_fn] || & &1,
        result_handler: opts[:result_handler]
      }
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{} = message, context) do
    prompt = context.prompt_fn.(message.data)
    
    case ClaudeCode.query(context.session, prompt) do
      {:ok, result} ->
        message
        |> Broadway.Message.update_data(fn _ -> result end)
        |> Broadway.Message.put_metadata(:status, :success)
        
      {:error, reason} ->
        Logger.error("Claude query failed: #{inspect(reason)}")
        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(_, messages, _batch_info, context) do
    if result_handler = context.result_handler do
      successful = Enum.filter(messages, &(&1.metadata.status == :success))
      result_handler.(successful)
    end
    
    messages
  end
end

# Usage example
defmodule MyApp.DocumentProcessor do
  def start_processing(documents) do
    ClaudeCode.Broadway.start_link(
      name: :doc_processor,
      producer: {Broadway.InMemoryProducer, documents},
      concurrency: 20,
      session: :analyzer,
      prompt_fn: &build_analysis_prompt/1,
      result_handler: &store_results/1
    )
  end
  
  defp build_analysis_prompt(doc) do
    "Analyze sentiment and extract key points from: #{doc.content}"
  end
  
  defp store_results(messages) do
    # Store batch results in database
    Enum.each(messages, fn msg ->
      Repo.insert!(%Analysis{
        document_id: msg.metadata.document_id,
        result: msg.data,
        analyzed_at: DateTime.utc_now()
      })
    end)
  end
end
```

#### 2.2 Rate Limiter Integration
```elixir
defmodule ClaudeCode.RateLimiter do
  use GenServer
  
  @default_limits %{
    requests_per_minute: 60,
    tokens_per_minute: 40_000
  }

  def check_and_update(limiter \\ __MODULE__, tokens) do
    GenServer.call(limiter, {:check_and_update, tokens})
  end

  @impl true
  def handle_call({:check_and_update, tokens}, _from, state) do
    now = System.monotonic_time(:millisecond)
    
    # Token bucket algorithm
    state = refill_tokens(state, now)
    
    if state.available_requests > 0 and state.available_tokens >= tokens do
      new_state = %{state |
        available_requests: state.available_requests - 1,
        available_tokens: state.available_tokens - tokens,
        last_update: now
      }
      {:reply, :ok, new_state}
    else
      wait_time = calculate_wait_time(state, tokens)
      {:reply, {:wait, wait_time}, state}
    end
  end
end
```

### Phase 3: Advanced Features (Week 3)

#### 3.1 Stream Processing
```elixir
defmodule ClaudeCode.Stream do
  @moduledoc """
  Stream processing utilities for real-time Claude integration.
  """

  def process_stream(stream, session, prompt_fn, opts \\ []) do
    window_size = opts[:window_size] || 10
    
    stream
    |> Stream.chunk_every(window_size)
    |> Stream.flat_map(fn chunk ->
      chunk
      |> Enum.map(&Task.async(fn -> 
        {&1, ClaudeCode.query(session, prompt_fn.(&1))}
      end))
      |> Task.await_many()
    end)
  end

  def windowed_analysis(stream, session, opts \\ []) do
    window_size = opts[:window_size] || 100
    
    stream
    |> Stream.chunk_every(window_size, window_size - 10)  # Overlapping windows
    |> Stream.map(fn window ->
      summary = ClaudeCode.query(session, 
        "Analyze trends in: #{inspect(window)}"
      )
      {window, summary}
    end)
  end
end
```

#### 3.2 Error Recovery
```elixir
defmodule ClaudeCode.Pipeline.Resilient do
  @doc """
  Process with automatic retry and dead letter queue.
  """
  def process_with_retry(items, session, prompt_fn, opts \\ []) do
    max_retries = opts[:max_retries] || 3
    
    {successful, failed} = items
    |> ClaudeCode.Flow.map(session, prompt_fn, opts)
    |> Flow.partition(fn {_item, result} ->
      match?({:ok, _}, result)
    end)
    
    # Retry failed items
    retried = failed
    |> retry_with_backoff(session, prompt_fn, max_retries)
    
    %{
      successful: successful ++ retried.successful,
      dead_letter: retried.failed
    }
  end
end
```

## Testing Strategy

1. **Unit Tests** - Test individual Flow/Broadway components with mocked sessions
2. **Integration Tests** - Test full pipelines with mock CLI
3. **Performance Tests** - Benchmark throughput and concurrency limits
4. **Property Tests** - Verify correct handling of various input types

## Documentation Plan

1. **Getting Started Guide** - Simple examples for common use cases
2. **Pipeline Cookbook** - Recipes for specific scenarios
3. **Performance Tuning** - Guidelines for optimal concurrency settings
4. **API Reference** - Complete module documentation

## Success Metrics

- Process 1000+ items with controlled concurrency
- Automatic rate limiting prevents API throttling  
- 80% less code compared to manual batch processing
- Zero changes to existing ClaudeCode API

## Timeline

- Week 1: Core Flow integration and basic pipelines
- Week 2: Broadway integration and rate limiting
- Week 3: Advanced features and documentation
- Week 4: Testing, benchmarking, and release preparation

## Conclusion

Broadway/Flow integration provides immediate value to ClaudeCode users by enabling efficient batch processing of AI workloads. This approach leverages Elixir's strengths without requiring architectural changes, making it the ideal next feature for the SDK.