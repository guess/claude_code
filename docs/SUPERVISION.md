# Production Supervision Guide

This guide covers how to use `ClaudeCode.Supervisor` for production-ready AI applications with fault tolerance, automatic restarts, and distributed session management.

## Why Use Supervision?

Traditional AI SDKs in Python/TypeScript struggle with:
- **Process crashes** losing application state
- **Manual session management** across application restarts
- **No fault tolerance** for long-running AI services
- **Difficulty scaling** to thousands of concurrent conversations

Elixir's OTP supervision solves these problems naturally, making it the **best choice for production AI applications**.

## Quick Start

### 1. Basic Supervised Setup

Add to your application's supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  api_key = System.fetch_env!("ANTHROPIC_API_KEY")
  
  children = [
    MyAppWeb.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :general_assistant, api_key: api_key],
      [name: :code_reviewer, api_key: api_key, system_prompt: "You review code for bugs and improvements"]
    ]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### 2. Use From Anywhere

Access supervised sessions from controllers, LiveViews, GenServers, or anywhere in your application:

```elixir
# From a Phoenix controller
def chat(conn, %{"message" => message}) do
  case ClaudeCode.query(:general_assistant, message) do
    {:ok, response} -> json(conn, %{response: response})
    {:error, _} -> conn |> put_status(500) |> json(%{error: "AI unavailable"})
  end
end

# From a GenServer
def handle_call({:get_review, code}, _from, state) do
  result = ClaudeCode.query(:code_reviewer, "Review: #{code}")
  {:reply, result, state}
end

# From a Task
Task.async(fn ->
  ClaudeCode.query(:general_assistant, "Analyze this data: #{data}")
end)
```

## Session Management Patterns

### Static Named Sessions (Recommended)

Best for long-lived assistants with specific roles:

```elixir
# Define specialized assistants in your supervision tree
{ClaudeCode.Supervisor, [
  # General purpose assistant
  [name: :assistant, api_key: api_key],
  
  # Specialized roles
  [name: :code_reviewer, api_key: api_key, 
   system_prompt: "You are an expert code reviewer focusing on Elixir best practices"],
   
  [name: :test_writer, api_key: api_key,
   system_prompt: "You write comprehensive ExUnit tests"],
   
  [name: :documentation_writer, api_key: api_key,
   system_prompt: "You write clear, concise documentation"],
   
  # Global session accessible across distributed nodes
  [name: {:global, :distributed_helper}, api_key: api_key]
]}
```

Use throughout your application:

```elixir
# Code review in your development workflow
{:ok, review} = ClaudeCode.query(:code_reviewer, """
Review this function for potential improvements:

#{File.read!("lib/my_module.ex")}
""")

# Test generation
{:ok, tests} = ClaudeCode.query(:test_writer, 
  "Write tests for UserController#create action")

# Documentation generation  
{:ok, docs} = ClaudeCode.query(:documentation_writer,
  "Document this API endpoint: POST /users")
```

### Dynamic Session Management

Add and remove sessions at runtime for user-specific or temporary contexts:

```elixir
# Start supervisor with some base sessions
{ClaudeCode.Supervisor, [
  [name: :shared_assistant, api_key: api_key]
]}

# Add user-specific sessions dynamically
def create_user_session(user_id, user_preferences) do
  ClaudeCode.Supervisor.start_session(ClaudeCode.Supervisor, [
    name: {:user_session, user_id},
    api_key: api_key,
    system_prompt: "You are helping user #{user_id}. Their preferences: #{user_preferences}"
  ])
end

# Use user session
def handle_user_query(user_id, message) do
  session_name = {:user_session, user_id}
  ClaudeCode.query(session_name, message)
end

# Clean up when user logs out
def cleanup_user_session(user_id) do
  session_name = {:user_session, user_id}
  ClaudeCode.Supervisor.terminate_session(ClaudeCode.Supervisor, session_name)
end
```

### Registry-Based Sessions

For more advanced session management with custom registries:

```elixir
# In your application setup
children = [
  {Registry, keys: :unique, name: MyApp.SessionRegistry},
  {ClaudeCode.Supervisor, [
    [name: {:via, Registry, {MyApp.SessionRegistry, :primary_assistant}}, api_key: api_key],
    [name: {:via, Registry, {MyApp.SessionRegistry, :backup_assistant}}, api_key: api_key]
  ]}
]

# Access via registry
session = {:via, Registry, {MyApp.SessionRegistry, :primary_assistant}}
ClaudeCode.query(session, "Help with this task")

# Find all sessions
Registry.keys(MyApp.SessionRegistry, self())
```

## Fault Tolerance Features

### Automatic Restart

Sessions automatically restart if they crash:

```elixir
# Session crashes are handled transparently
{:ok, response} = ClaudeCode.query(:assistant, "Complex task")
# Even if :assistant crashes during processing, it restarts automatically
# Next query works normally (though conversation history is lost)
{:ok, response2} = ClaudeCode.query(:assistant, "Another task")
```

### Independent Failure Isolation

Individual session crashes don't affect others:

```elixir
# If :code_reviewer crashes, :test_writer continues working
try do
  ClaudeCode.query(:code_reviewer, malformed_input)
catch
  # This won't affect other sessions
  :error, _ -> :crashed
end

# :test_writer still works fine
{:ok, tests} = ClaudeCode.query(:test_writer, "Write tests for User model")
```

### Supervisor Management

Monitor and manage your sessions:

```elixir
# List all active sessions
sessions = ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)
#=> [{:assistant, #PID<0.123.0>, :worker, [ClaudeCode.Session]}, ...]

# Get session count
count = ClaudeCode.Supervisor.count_sessions(ClaudeCode.Supervisor)
#=> 3

# Restart a specific session (clears conversation history)
:ok = ClaudeCode.Supervisor.restart_session(ClaudeCode.Supervisor, :assistant)

# Add new session at runtime
{:ok, _pid} = ClaudeCode.Supervisor.start_session(ClaudeCode.Supervisor, [
  name: :temporary_helper,
  api_key: api_key,
  system_prompt: "Temporary assistant"
])

# Remove session when no longer needed
:ok = ClaudeCode.Supervisor.terminate_session(ClaudeCode.Supervisor, :temporary_helper)
```

## Real-World Examples

### Web Application with Multiple AI Assistants

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  api_key = System.fetch_env!("ANTHROPIC_API_KEY")
  
  children = [
    MyAppWeb.Endpoint,
    {Registry, keys: :unique, name: MyApp.AIRegistry},
    {ClaudeCode.Supervisor, [
      # Customer support assistant
      [name: {:via, Registry, {MyApp.AIRegistry, :customer_support}}, 
       api_key: api_key,
       system_prompt: "You provide helpful customer support for our SaaS platform"],
       
      # Developer assistant  
      [name: {:via, Registry, {MyApp.AIRegistry, :dev_assistant}},
       api_key: api_key,
       system_prompt: "You help developers integrate our API"],
       
      # Content moderator
      [name: {:via, Registry, {MyApp.AIRegistry, :moderator}},
       api_key: api_key,
       system_prompt: "You moderate user content for policy violations"],
       
      # Analytics assistant
      [name: {:via, Registry, {MyApp.AIRegistry, :analytics}},
       api_key: api_key,
       system_prompt: "You analyze data and generate business insights"]
    ]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# lib/my_app_web/controllers/support_controller.ex
defmodule MyAppWeb.SupportController do
  def chat(conn, %{"message" => message, "context" => context}) do
    session = {:via, Registry, {MyApp.AIRegistry, :customer_support}}
    
    prompt = """
    Customer context: #{context}
    Customer message: #{message}
    
    Please provide helpful support.
    """
    
    case ClaudeCode.query(session, prompt) do
      {:ok, response} ->
        json(conn, %{response: response})
      {:error, reason} ->
        Logger.error("Support AI failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: "Support temporarily unavailable"})
    end
  end
end

# lib/my_app_web/live/analytics_live.ex
defmodule MyAppWeb.AnalyticsLive do
  use MyAppWeb, :live_view
  
  def handle_event("analyze_data", %{"data" => data}, socket) do
    session = {:via, Registry, {MyApp.AIRegistry, :analytics}}
    parent = self()
    
    # Stream analysis results in real-time
    Task.start(fn ->
      session
      |> ClaudeCode.query_stream("Analyze this data and provide insights: #{data}")
      |> ClaudeCode.Stream.text_content()
      |> Enum.each(fn text ->
        send(parent, {:analysis_chunk, text})
      end)
      
      send(parent, :analysis_complete)
    end)
    
    {:noreply, assign(socket, :analyzing, true)}
  end
  
  def handle_info({:analysis_chunk, text}, socket) do
    {:noreply, push_event(socket, "analysis_text", %{text: text})}
  end
  
  def handle_info(:analysis_complete, socket) do
    {:noreply, assign(socket, :analyzing, false)}
  end
end
```

### Distributed Multi-Node Setup

```elixir
# Node 1: Web frontend
children = [
  MyAppWeb.Endpoint,
  {ClaudeCode.Supervisor, [
    [name: {:global, :web_assistant}, api_key: api_key],
    [name: {:global, :user_support}, api_key: api_key]
  ]}
]

# Node 2: Background processing
children = [
  MyApp.JobProcessor,
  {ClaudeCode.Supervisor, [
    [name: {:global, :data_processor}, api_key: api_key],
    [name: {:global, :report_generator}, api_key: api_key]
  ]}
]

# Any node can access any global session
ClaudeCode.query({:global, :data_processor}, "Process this batch: #{data}")
ClaudeCode.query({:global, :report_generator}, "Generate monthly report")
```

### Microservice Architecture

Each service manages its own AI capabilities:

```elixir
# User Service
def start(_type, _args) do
  children = [
    UserService.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :user_onboarding, api_key: api_key, 
       system_prompt: "You help onboard new users"],
      [name: :user_support, api_key: api_key,
       system_prompt: "You provide user account support"]
    ]}
  ]
end

# Analytics Service  
def start(_type, _args) do
  children = [
    AnalyticsService.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :data_analyzer, api_key: api_key,
       system_prompt: "You analyze user behavior data"],
      [name: :report_generator, api_key: api_key,
       system_prompt: "You generate business reports"]
    ]}
  ]
end

# Content Service
def start(_type, _args) do
  children = [
    ContentService.Endpoint,
    {ClaudeCode.Supervisor, [
      [name: :content_moderator, api_key: api_key,
       system_prompt: "You moderate user content"],
      [name: :content_enhancer, api_key: api_key,
       system_prompt: "You improve content quality"]
    ]}
  ]
end
```

## Configuration Best Practices

### Environment-Based Configuration

```elixir
# config/config.exs
config :claude_code,
  api_key: {:system, "ANTHROPIC_API_KEY"},
  timeout: 300_000,
  permission_mode: :default

# config/prod.exs
config :claude_code,
  timeout: 600_000,  # Longer timeouts in production
  permission_mode: :accept_edits  # More permissive for production

# config/test.exs
config :claude_code,
  api_key: "test-key",
  timeout: 30_000  # Faster timeouts for testing
```

### Session-Specific Configuration

```elixir
{ClaudeCode.Supervisor, [
  # Fast assistant for simple queries
  [name: :quick_helper, 
   api_key: api_key,
   timeout: 30_000,
   max_turns: 5],
   
  # Deep analysis assistant
  [name: :deep_analyzer,
   api_key: api_key, 
   timeout: 600_000,
   max_turns: 50,
   system_prompt: "You perform thorough analysis with detailed explanations"],
   
  # Code assistant with file access
  [name: :code_assistant,
   api_key: api_key,
   allowed_tools: ["View", "Edit", "Bash(git:*)"],
   add_dir: ["/app/lib", "/app/test"],
   system_prompt: "You are an expert Elixir developer"]
]}
```

## Monitoring and Observability

### Health Checks

```elixir
defmodule MyApp.HealthCheck do
  def ai_services_status do
    sessions = ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)
    
    %{
      total_sessions: length(sessions),
      active_sessions: Enum.count(sessions, fn {_id, pid, _type, _modules} ->
        Process.alive?(pid)
      end),
      session_details: Enum.map(sessions, fn {id, pid, _type, _modules} ->
        %{
          name: id,
          alive: Process.alive?(pid),
          pid: inspect(pid)
        }
      end)
    }
  end
  
  def test_ai_connectivity do
    try do
      case ClaudeCode.query(:general_assistant, "Hello", timeout: 10_000) do
        {:ok, _response} -> :healthy
        {:error, reason} -> {:unhealthy, reason}
      end
    catch
      :exit, {:timeout, _} -> {:unhealthy, :timeout}
      :error, reason -> {:unhealthy, reason}
    end
  end
end
```

### Logging and Metrics

```elixir
defmodule MyApp.AIMetrics do
  require Logger
  
  def log_query(session_name, prompt, result, duration) do
    Logger.info("AI Query", 
      session: session_name,
      prompt_length: String.length(prompt),
      result: elem(result, 0),
      duration_ms: duration
    )
    
    # Send to your metrics system
    :telemetry.execute([:myapp, :ai, :query], 
      %{duration: duration}, 
      %{session: session_name, success: elem(result, 0) == :ok}
    )
  end
end

# Wrapper for instrumented queries
defmodule MyApp.AI do
  def query(session, prompt, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    result = ClaudeCode.query(session, prompt, opts)
    
    duration = System.monotonic_time(:millisecond) - start_time
    MyApp.AIMetrics.log_query(session, prompt, result, duration)
    
    result
  end
end
```

## Performance Considerations

### Session Pooling for High Load

```elixir
defmodule MyApp.AIPool do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def checkout do
    GenServer.call(__MODULE__, :checkout)
  end
  
  def checkin(session) do
    GenServer.cast(__MODULE__, {:checkin, session})
  end
  
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 10)
    api_key = Keyword.fetch!(opts, :api_key)
    
    # Start pool of sessions
    sessions = for i <- 1..pool_size do
      {:ok, session} = ClaudeCode.start_link(api_key: api_key)
      session
    end
    
    {:ok, %{available: sessions, in_use: MapSet.new()}}
  end
  
  def handle_call(:checkout, _from, %{available: []} = state) do
    {:reply, {:error, :pool_exhausted}, state}
  end
  
  def handle_call(:checkout, _from, %{available: [session | rest]} = state) do
    new_state = %{state | 
      available: rest,
      in_use: MapSet.put(state.in_use, session)
    }
    {:reply, {:ok, session}, new_state}
  end
  
  def handle_cast({:checkin, session}, state) do
    if MapSet.member?(state.in_use, session) do
      new_state = %{state |
        available: [session | state.available],
        in_use: MapSet.delete(state.in_use, session)
      }
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
end

# Usage
{:ok, session} = MyApp.AIPool.checkout()
result = ClaudeCode.query(session, prompt)
MyApp.AIPool.checkin(session)
```

### Load Balancing Multiple Sessions

```elixir
defmodule MyApp.LoadBalancer do
  def query_with_load_balancing(prompt, opts \\ []) do
    sessions = [:assistant_1, :assistant_2, :assistant_3, :assistant_4]
    session = Enum.random(sessions)
    
    ClaudeCode.query(session, prompt, opts)
  end
  
  def query_with_round_robin(prompt, opts \\ []) do
    session = :persistent_term.get(:current_session, :assistant_1)
    
    next_session = case session do
      :assistant_1 -> :assistant_2
      :assistant_2 -> :assistant_3  
      :assistant_3 -> :assistant_4
      :assistant_4 -> :assistant_1
    end
    
    :persistent_term.put(:current_session, next_session)
    
    ClaudeCode.query(session, prompt, opts)
  end
end
```

## Testing Supervised Sessions

### Mock Sessions for Testing

```elixir
# test/support/test_helpers.ex
defmodule MyApp.TestHelpers do
  def start_test_supervisor do
    children = [
      {ClaudeCode.Supervisor, [
        [name: :test_assistant, api_key: "test-key"]
      ]}
    ]
    
    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
    supervisor
  end
  
  def mock_claude_response(session, response) do
    # Use mox or similar to mock responses
    # This is pseudocode - implement based on your testing strategy
    allow(ClaudeCode.Session, :query, fn ^session, _prompt, _opts ->
      {:ok, response}
    end)
  end
end

# test/my_app_web/controllers/support_controller_test.exs
defmodule MyAppWeb.SupportControllerTest do
  use MyAppWeb.ConnCase
  import MyApp.TestHelpers
  
  setup do
    supervisor = start_test_supervisor()
    on_exit(fn -> Supervisor.stop(supervisor) end)
    %{supervisor: supervisor}
  end
  
  test "responds to support queries", %{conn: conn} do
    mock_claude_response(:test_assistant, "I can help you with that!")
    
    conn = post(conn, "/support/chat", %{
      "message" => "I need help",
      "context" => "billing issue"
    })
    
    assert json_response(conn, 200) == %{
      "response" => "I can help you with that!"
    }
  end
end
```

### Integration Testing

```elixir
# test/integration/ai_workflow_test.exs
defmodule MyApp.AIWorkflowTest do
  use ExUnit.Case
  
  @moduletag :integration
  
  setup do
    # Only run if real API key is available
    api_key = System.get_env("ANTHROPIC_API_KEY")
    if api_key do
      {:ok, supervisor} = ClaudeCode.Supervisor.start_link([
        [name: :integration_test, api_key: api_key]
      ])
      
      on_exit(fn -> Supervisor.stop(supervisor) end)
      %{api_key: api_key}
    else
      {:skip, "No API key for integration testing"}
    end
  end
  
  test "full AI workflow", %{api_key: _api_key} do
    # Test real AI interaction
    {:ok, response} = ClaudeCode.query(:integration_test, "Hello, respond with just 'Hello!'")
    assert String.contains?(response, "Hello")
    
    # Test session continuity
    {:ok, response2} = ClaudeCode.query(:integration_test, "What did I just say?")
    assert String.contains?(String.downcase(response2), "hello")
  end
end
```

## Migration from Single Sessions

If you're currently using single sessions, here's how to migrate:

### Before (Single Sessions)

```elixir
# In application.ex
children = [
  MyAppWeb.Endpoint,
  {ClaudeCode, [name: :claude_session, api_key: api_key]}
]

# Usage throughout app
ClaudeCode.query(:claude_session, prompt)
```

### After (Supervised Sessions)

```elixir
# In application.ex - minimal change
children = [
  MyAppWeb.Endpoint,
  {ClaudeCode.Supervisor, [
    [name: :claude_session, api_key: api_key]  # Same name, now supervised
  ]}
]

# Usage stays exactly the same!
ClaudeCode.query(:claude_session, prompt)
```

### Gradual Migration

```elixir
# Phase 1: Add supervisor alongside existing session
children = [
  MyAppWeb.Endpoint,
  {ClaudeCode, [name: :legacy_session, api_key: api_key]},  # Keep existing
  {ClaudeCode.Supervisor, [
    [name: :new_assistant, api_key: api_key]  # Add new supervised session
  ]}
]

# Phase 2: Gradually migrate calls to new session
# Old: ClaudeCode.query(:legacy_session, prompt)  
# New: ClaudeCode.query(:new_assistant, prompt)

# Phase 3: Remove legacy session once migration complete
children = [
  MyAppWeb.Endpoint,
  {ClaudeCode.Supervisor, [
    [name: :new_assistant, api_key: api_key]
  ]}
]
```

## Troubleshooting

### Common Issues

**Session Not Found Error:**
```elixir
# Problem: Trying to use session before it's started
ClaudeCode.query(:nonexistent_session, prompt)
#=> ** (EXIT) no process: the process is not alive or there's no process currently associated with the given name

# Solution: Check session is in supervision tree
sessions = ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)
IO.inspect(sessions)
```

**Session Keeps Crashing:**
```elixir
# Problem: Invalid configuration causing repeated crashes
# Check logs for specific error

# Solution: Validate configuration
valid_config = [
  name: :test_session,
  api_key: System.fetch_env!("ANTHROPIC_API_KEY"),  # Make sure this exists
  timeout: 60_000,  # Reasonable timeout
  allowed_tools: ["View"]  # Valid tools only
]
```

**Memory Usage Growing:**
```elixir
# Problem: Too many dynamic sessions not being cleaned up
# Monitor session count
count = ClaudeCode.Supervisor.count_sessions(ClaudeCode.Supervisor)

# Solution: Implement cleanup
def cleanup_old_user_sessions do
  sessions = ClaudeCode.Supervisor.list_sessions(ClaudeCode.Supervisor)
  
  for {session_id, _pid, _type, _modules} <- sessions do
    case session_id do
      {:user_session, user_id} ->
        if user_inactive?(user_id) do
          ClaudeCode.Supervisor.terminate_session(ClaudeCode.Supervisor, session_id)
        end
      _ -> :ok
    end
  end
end
```

### Debug Mode

```elixir
# Enable debug logging
Logger.configure(level: :debug)

# Monitor supervisor state
:sys.get_state(ClaudeCode.Supervisor)

# Check individual session state
session_pid = Process.whereis(:my_session)
:sys.get_state(session_pid)
```

## Summary

ClaudeCode's supervision system provides:

- **✅ Fault Tolerance** - Sessions restart automatically on crashes
- **✅ Zero Downtime** - Hot code reloading preserves session state  
- **✅ Global Access** - Named sessions work from anywhere in your app
- **✅ Distributed Support** - Sessions work across Elixir clusters
- **✅ Dynamic Management** - Add/remove sessions at runtime
- **✅ Resource Efficiency** - Idle sessions use minimal memory
- **✅ Production Ready** - Battle-tested OTP supervision patterns

This makes Elixir the **superior choice for production AI applications** compared to Python/TypeScript SDKs that lack these critical operational capabilities.

Choose supervision for any production application, distributed system, or long-running AI service. Use single sessions only for scripts, prototypes, or simple one-off tasks.