# Agent Workflows for ClaudeCode Elixir SDK

## Executive Summary

This proposal outlines recommended patterns and designs for implementing agent workflows in the ClaudeCode Elixir SDK. Rather than building a complex agent framework, we recommend leveraging Elixir's existing strengths in concurrent systems design to enable powerful agent patterns through composition and supervision.

## What Are Agents in LLM Context?

In the context of LLMs, agents are autonomous or semi-autonomous systems that:
1. **Break down complex tasks** into smaller, manageable steps
2. **Maintain state and context** across multiple interactions
3. **Use tools** to interact with external systems
4. **Make decisions** based on intermediate results
5. **Coordinate** with other agents for complex workflows

## Recommended Approach: Composition Over Framework

Instead of building a heavy agent framework, we recommend providing composable patterns that leverage Elixir's strengths:

1. **GenServer-based Agents** - Each agent is a supervised process
2. **Process-based Memory** - State lives in processes, not databases
3. **Message Passing** - Agents communicate via Elixir messages
4. **Supervision Trees** - Fault-tolerant agent systems
5. **Function Composition** - Build complex behaviors from simple parts

## Core Agent Patterns

### 1. Specialized Agent Pattern

Different agents with specific expertise working independently:

```elixir
defmodule MyApp.Agents do
  use Supervisor

  def start_link(api_key) do
    Supervisor.start_link(__MODULE__, api_key, name: __MODULE__)
  end

  @impl true
  def init(api_key) do
    children = [
      # Code review specialist
      {ClaudeCode, [
        api_key: api_key,
        name: :reviewer,
        system_prompt: """
        You are a senior code reviewer. Focus on:
        - Security vulnerabilities
        - Performance issues
        - Code smells
        - Best practices
        Output format: {:issues, [...], :suggestions, [...]}
        """
      ]},
      
      # Test generation specialist
      {ClaudeCode, [
        api_key: api_key,
        name: :test_writer,
        system_prompt: """
        You write comprehensive ExUnit tests.
        - Cover edge cases
        - Use property-based testing when appropriate
        - Follow AAA pattern
        - Include doctest examples
        """
      ]},
      
      # Documentation specialist
      {ClaudeCode, [
        api_key: api_key,
        name: :documenter,
        system_prompt: """
        You write clear, comprehensive documentation.
        - Module docs with examples
        - Function specs with @doc and @spec
        - README updates
        - Architecture diagrams in Mermaid
        """
      ]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Convenience functions
  def review_code(file_path) do
    code = File.read!(file_path)
    ClaudeCode.query(:reviewer, "Review this code:\n\n#{code}")
  end

  def generate_tests(module_path) do
    code = File.read!(module_path)
    ClaudeCode.query(:test_writer, "Generate tests for:\n\n#{code}")
  end

  def document_module(module_path) do
    code = File.read!(module_path)
    ClaudeCode.query(:documenter, "Document this module:\n\n#{code}")
  end
end
```

### 2. Orchestrator Agent Pattern

A coordinator that delegates tasks to specialized agents:

```elixir
defmodule MyApp.ProjectAnalyzer do
  use GenServer
  require Logger

  defstruct [:coordinator, :agents, :current_analysis, :results]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def analyze_project(analyzer \\ __MODULE__, project_path) do
    GenServer.call(analyzer, {:analyze, project_path}, :infinity)
  end

  @impl true
  def init(opts) do
    # Start coordinator agent
    {:ok, coordinator} = ClaudeCode.start_link(
      api_key: opts[:api_key],
      system_prompt: """
      You are a project analysis coordinator. Your role:
      1. Break down analysis tasks
      2. Delegate to appropriate specialists
      3. Synthesize results
      4. Provide actionable recommendations
      """
    )

    state = %__MODULE__{
      coordinator: coordinator,
      agents: %{
        security: :security_auditor,
        performance: :performance_analyzer,
        quality: :code_quality_checker,
        architecture: :architecture_reviewer
      },
      results: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:analyze, project_path}, _from, state) do
    # Step 1: Coordinator creates analysis plan
    {:ok, plan} = ClaudeCode.query(state.coordinator,
      "Create an analysis plan for project at #{project_path}. List specific files and aspects to analyze."
    )

    # Step 2: Parse plan and delegate tasks
    tasks = parse_analysis_plan(plan)
    
    # Step 3: Execute tasks in parallel
    results = tasks
    |> Enum.map(fn {type, task} ->
      Task.async(fn ->
        agent = Map.get(state.agents, type)
        {:ok, result} = ClaudeCode.query(agent, task)
        {type, result}
      end)
    end)
    |> Task.await_many(300_000)  # 5 minute timeout
    |> Map.new()

    # Step 4: Coordinator synthesizes results
    {:ok, summary} = ClaudeCode.query(state.coordinator,
      "Synthesize these analysis results into actionable recommendations:\n#{inspect(results)}"
    )

    {:reply, {:ok, summary, results}, state}
  end

  defp parse_analysis_plan(plan) do
    # Extract specific tasks from coordinator's plan
    # This would parse the structured output from Claude
    [
      {:security, "Analyze security in auth.ex and crypto.ex"},
      {:performance, "Check database queries in repo.ex"},
      {:quality, "Review code quality in core modules"},
      {:architecture, "Evaluate overall system design"}
    ]
  end
end
```

### 3. Conversational Agent with Memory

An agent that maintains conversation state and learns from interactions:

```elixir
defmodule MyApp.ConversationalAgent do
  use GenServer
  
  defstruct [:session, :memory, :context_window, :preferences]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def chat(agent, message) do
    GenServer.call(agent, {:chat, message}, 30_000)
  end

  def remember(agent, fact) do
    GenServer.cast(agent, {:remember, fact})
  end

  def forget(agent, topic) do
    GenServer.cast(agent, {:forget, topic})
  end

  @impl true
  def init(opts) do
    {:ok, session} = ClaudeCode.start_link(
      api_key: opts[:api_key],
      system_prompt: opts[:system_prompt] || default_prompt()
    )

    state = %__MODULE__{
      session: session,
      memory: %{
        facts: [],
        preferences: %{},
        conversation_history: []
      },
      context_window: opts[:context_window] || 10,
      preferences: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:chat, message}, _from, state) do
    # Build context from memory
    context = build_context(state)
    
    # Include memory in the query
    full_prompt = """
    #{context}
    
    Current message: #{message}
    
    Respond naturally while considering the context and any remembered facts.
    """
    
    {:ok, response} = ClaudeCode.query(state.session, full_prompt)
    
    # Update conversation history
    new_state = update_history(state, message, response)
    
    # Extract any facts to remember from the conversation
    new_state = extract_and_store_facts(new_state, message, response)
    
    {:reply, {:ok, response}, new_state}
  end

  @impl true
  def handle_cast({:remember, fact}, state) do
    new_memory = Map.update(state.memory, :facts, [fact], &[fact | &1])
    {:noreply, %{state | memory: new_memory}}
  end

  @impl true
  def handle_cast({:forget, topic}, state) do
    new_facts = Enum.reject(state.memory.facts, &String.contains?(&1, topic))
    new_memory = Map.put(state.memory, :facts, new_facts)
    {:noreply, %{state | memory: new_memory}}
  end

  defp build_context(state) do
    recent_history = state.memory.conversation_history
    |> Enum.take(state.context_window)
    |> Enum.reverse()
    |> Enum.map(fn {user, assistant} ->
      "User: #{user}\nAssistant: #{assistant}"
    end)
    |> Enum.join("\n\n")

    facts = case state.memory.facts do
      [] -> ""
      facts -> "\nRemembered facts:\n" <> Enum.join(facts, "\n")
    end

    """
    Previous conversation:
    #{recent_history}
    #{facts}
    """
  end

  defp update_history(state, message, response) do
    new_history = [{message, response} | state.memory.conversation_history]
    new_memory = Map.put(state.memory, :conversation_history, new_history)
    %{state | memory: new_memory}
  end

  defp extract_and_store_facts(state, _message, response) do
    # This could use Claude to extract facts
    # For now, we'll just return the state unchanged
    state
  end

  defp default_prompt do
    """
    You are a helpful assistant with memory capabilities.
    You can remember facts about users and conversations.
    Be conversational and reference previous context when relevant.
    """
  end
end
```

### 4. Tool-Using Agent Pattern

Agents use tools through the standard `allowed_tools` and `mcp_config` options:

```elixir
defmodule MyApp.ToolAgent do
  @moduledoc """
  An autonomous agent that uses Claude's built-in tools and MCP servers.
  """
  
  def start_link(opts) do
    # Configure with specific tools
    {:ok, session} = ClaudeCode.start_link(
      api_key: opts[:api_key],
      name: opts[:name],
      system_prompt: """
      You are an autonomous agent that accomplishes tasks using tools.
      Plan your approach, then execute step by step.
      Available tools will be shown in the system message.
      """,
      # Standard Claude tools
      allowed_tools: ["View", "Edit", "Bash", "Search", "Browse"],
      # MCP server configuration
      mcp_config: %{
        "github" => %{
          "command" => "npx",
          "args" => ["@modelcontextprotocol/server-github"],
          "env" => %{"GITHUB_PERSONAL_ACCESS_TOKEN" => opts[:github_token]}
        },
        "postgres" => %{
          "command" => "npx", 
          "args" => ["@modelcontextprotocol/server-postgres", opts[:db_url]]
        }
      }
    )
    
    {:ok, session}
  end

  def execute_task(session, task_description) do
    # Claude will automatically use the configured tools
    ClaudeCode.query(session, task_description)
  end

  # Example: Code analysis agent with GitHub integration
  def analyze_repository(repo_url) do
    {:ok, agent} = start_link(
      api_key: api_key(),
      name: :repo_analyzer,
      github_token: System.get_env("GITHUB_TOKEN")
    )
    
    execute_task(agent, """
    Analyze the repository at #{repo_url}:
    1. Clone and examine the code structure
    2. Identify potential security issues
    3. Check for code quality problems
    4. Review documentation completeness
    5. Create a comprehensive report
    """)
  end
end
```

### 5. Multi-Agent Collaboration Pattern

Multiple agents working together on complex tasks:

```elixir
defmodule MyApp.CollaborativeAgents do
  @moduledoc """
  A system where multiple agents collaborate via a shared message bus.
  """
  
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      # Message bus for agent communication
      {Registry, keys: :duplicate, name: AgentRegistry},
      {MyApp.AgentMessageBus, []},
      
      # Specialized agents that can communicate
      {MyApp.ResearchAgent, opts},
      {MyApp.WriterAgent, opts},
      {MyApp.EditorAgent, opts},
      {MyApp.FactCheckerAgent, opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end

defmodule MyApp.AgentMessageBus do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def publish(topic, message) do
    GenServer.cast(__MODULE__, {:publish, topic, message})
  end

  def subscribe(topic) do
    Registry.register(AgentRegistry, topic, [])
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:publish, topic, message}, state) do
    Registry.dispatch(AgentRegistry, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:agent_message, topic, message})
    end)
    
    {:noreply, state}
  end
end

defmodule MyApp.ResearchAgent do
  use GenServer
  alias MyApp.AgentMessageBus

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def research_topic(topic) do
    GenServer.call(__MODULE__, {:research, topic}, :infinity)
  end

  @impl true
  def init(opts) do
    {:ok, session} = ClaudeCode.start_link(
      api_key: opts[:api_key],
      system_prompt: """
      You are a research specialist. Your role:
      1. Gather comprehensive information on topics
      2. Verify facts from multiple sources
      3. Organize findings clearly
      4. Communicate with other agents via messages
      
      When you complete research, announce: "RESEARCH_COMPLETE: <topic>"
      """
    )

    # Subscribe to relevant topics
    AgentMessageBus.subscribe("research_request")
    AgentMessageBus.subscribe("fact_check_request")

    {:ok, %{session: session, current_research: nil}}
  end

  @impl true
  def handle_call({:research, topic}, _from, state) do
    {:ok, research} = ClaudeCode.query(state.session,
      "Research the topic: #{topic}. Provide comprehensive findings."
    )
    
    # Notify other agents
    AgentMessageBus.publish("research_complete", %{
      topic: topic,
      findings: research,
      agent: :research
    })
    
    {:reply, {:ok, research}, %{state | current_research: research}}
  end

  @impl true
  def handle_info({:agent_message, "fact_check_request", %{claim: claim}}, state) do
    # Help fact checker with research
    {:ok, result} = ClaudeCode.query(state.session,
      "Fact check this claim using your research: #{claim}"
    )
    
    AgentMessageBus.publish("fact_check_response", %{
      claim: claim,
      result: result,
      agent: :research
    })
    
    {:noreply, state}
  end
end
```

## Real-World Use Cases

### 1. Code Review Pipeline

```elixir
defmodule MyApp.CodeReviewPipeline do
  @moduledoc """
  Automated code review with multiple specialized agents.
  """
  
  def review_pull_request(pr_url) do
    with {:ok, files} <- fetch_pr_files(pr_url),
         {:ok, security_issues} <- security_review(files),
         {:ok, performance_issues} <- performance_review(files),
         {:ok, style_issues} <- style_review(files),
         {:ok, test_coverage} <- test_coverage_review(files) do
      
      # Synthesize all reviews
      ClaudeCode.query(:review_synthesizer, """
      Combine these reviews into a comprehensive PR review:
      
      Security: #{inspect(security_issues)}
      Performance: #{inspect(performance_issues)}
      Style: #{inspect(style_issues)}
      Test Coverage: #{inspect(test_coverage)}
      
      Format as a GitHub PR comment with:
      - Summary
      - Critical issues (must fix)
      - Suggestions (nice to have)
      - Positive feedback
      """)
    end
  end
end
```

### 2. Documentation Generator

```elixir
defmodule MyApp.DocGenerator do
  @moduledoc """
  Multi-agent documentation generation system.
  """
  
  def generate_project_docs(project_path) do
    # Analyze project structure
    {:ok, structure} = ClaudeCode.query(:architect, 
      "Analyze project structure at #{project_path}"
    )
    
    # Generate different types of documentation in parallel
    tasks = [
      Task.async(fn -> generate_api_docs(project_path) end),
      Task.async(fn -> generate_guides(structure) end),
      Task.async(fn -> generate_examples(project_path) end),
      Task.async(fn -> generate_architecture_diagrams(structure) end)
    ]
    
    [api_docs, guides, examples, diagrams] = Task.await_many(tasks)
    
    # Combine into cohesive documentation
    ClaudeCode.query(:doc_editor, """
    Create a comprehensive documentation structure from:
    - API Docs: #{api_docs}
    - Guides: #{guides}
    - Examples: #{examples}
    - Diagrams: #{diagrams}
    
    Output as markdown files with proper organization.
    """)
  end
end
```

### 3. Refactoring Assistant

```elixir
defmodule MyApp.RefactoringAssistant do
  @moduledoc """
  Intelligent refactoring with test validation.
  """
  
  def refactor_module(module_path, refactoring_type) do
    # Read current code
    code = File.read!(module_path)
    
    # Generate refactoring plan
    {:ok, plan} = ClaudeCode.query(:refactoring_planner, """
    Create a refactoring plan for #{refactoring_type}:
    
    Current code:
    #{code}
    
    Include:
    1. Step-by-step changes
    2. Risk assessment
    3. Required test updates
    """)
    
    # Execute refactoring
    {:ok, refactored} = ClaudeCode.query(:refactorer, """
    Apply this refactoring plan:
    #{plan}
    
    To this code:
    #{code}
    """)
    
    # Update tests
    {:ok, updated_tests} = ClaudeCode.query(:test_updater, """
    Update tests for these refactoring changes:
    
    Original: #{code}
    Refactored: #{refactored}
    Plan: #{plan}
    """)
    
    # Validate changes
    validation_result = validate_refactoring(
      module_path, 
      refactored, 
      updated_tests
    )
    
    case validation_result do
      :ok -> 
        apply_changes(module_path, refactored, updated_tests)
      {:error, reason} ->
        {:error, "Refactoring validation failed: #{reason}"}
    end
  end
end
```

### 4. Learning Assistant

```elixir
defmodule MyApp.LearningAssistant do
  @moduledoc """
  Personalized learning assistant that adapts to user's knowledge level.
  """
  
  use GenServer
  
  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via_tuple(user_id))
  end
  
  def learn_topic(user_id, topic) do
    GenServer.call(via_tuple(user_id), {:learn, topic}, :infinity)
  end
  
  @impl true
  def init(user_id) do
    # Load user's learning profile
    profile = load_or_create_profile(user_id)
    
    {:ok, teacher} = ClaudeCode.start_link(
      api_key: api_key(),
      system_prompt: build_teacher_prompt(profile)
    )
    
    {:ok, assessor} = ClaudeCode.start_link(
      api_key: api_key(),
      system_prompt: "You assess understanding and provide feedback."
    )
    
    state = %{
      user_id: user_id,
      profile: profile,
      teacher: teacher,
      assessor: assessor,
      current_lesson: nil
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:learn, topic}, _from, state) do
    # Assess current knowledge
    {:ok, assessment} = ClaudeCode.query(state.assessor, """
    Assess knowledge level for #{topic} based on profile:
    #{inspect(state.profile)}
    
    Rate 1-10 and identify gaps.
    """)
    
    # Create personalized lesson
    {:ok, lesson} = ClaudeCode.query(state.teacher, """
    Create a lesson for #{topic} based on:
    - Assessment: #{assessment}
    - Learning style: #{state.profile.learning_style}
    - Previous topics: #{inspect(state.profile.completed_topics)}
    
    Include examples relevant to their interests: #{inspect(state.profile.interests)}
    """)
    
    # Update profile
    new_profile = update_profile(state.profile, topic, assessment)
    
    {:reply, {:ok, lesson}, %{state | profile: new_profile}}
  end
  
  defp via_tuple(user_id) do
    {:via, Registry, {LearningRegistry, user_id}}
  end
  
  defp build_teacher_prompt(profile) do
    """
    You are a personalized teacher for a student with:
    - Learning style: #{profile.learning_style}
    - Current level: #{profile.skill_level}
    - Interests: #{inspect(profile.interests)}
    
    Adapt your teaching to their level and style.
    Use analogies from their interests.
    Build on their existing knowledge.
    """
  end
end
```

## Implementation Recommendations

### 1. Start Simple

Begin with basic specialized agents using the existing ClaudeCode supervision:

```elixir
# In your supervision tree
children = [
  {ClaudeCode.Supervisor, [
    [name: :researcher, api_key: key, system_prompt: research_prompt],
    [name: :writer, api_key: key, system_prompt: writer_prompt],
    [name: :reviewer, api_key: key, system_prompt: review_prompt]
  ]}
]
```

### 2. Add Agent Coordination

Build a simple coordinator module:

```elixir
defmodule ClaudeCode.AgentCoordinator do
  @moduledoc """
  Coordinates multiple ClaudeCode sessions for complex workflows.
  """
  
  def pipeline(agents, task) do
    # Sequential pipeline
  end
  
  def parallel(agents, tasks) do
    # Parallel execution
  end
  
  def delegate(coordinator, task, agents) do
    # Coordinator delegates to specialists
  end
end
```

### 3. Memory Patterns

Leverage process state for memory:

```elixir
defmodule ClaudeCode.StatefulAgent do
  @moduledoc """
  An agent that maintains state between queries.
  """
  
  use GenServer
  
  # Wraps ClaudeCode.Session with additional state
  def query_with_memory(agent, prompt) do
    GenServer.call(agent, {:query_with_memory, prompt})
  end
end
```

### 4. Tool Configuration

Configure agents with appropriate tools using the standard options:

```elixir
defmodule ClaudeCode.AgentTools do
  @moduledoc """
  Tool configurations for different agent types.
  """
  
  def researcher_tools do
    [
      allowed_tools: ["View", "Search", "Browse"],
      mcp_config: %{
        "fetch" => %{
          "command" => "npx",
          "args" => ["@modelcontextprotocol/server-fetch"]
        }
      }
    ]
  end
  
  def developer_tools do
    [
      allowed_tools: ["View", "Edit", "Bash", "Search"],
      mcp_config: %{
        "github" => %{
          "command" => "npx",
          "args" => ["@modelcontextprotocol/server-github"],
          "env" => %{"GITHUB_PERSONAL_ACCESS_TOKEN" => System.get_env("GITHUB_TOKEN")}
        }
      }
    ]
  end
  
  def analyst_tools do
    [
      allowed_tools: ["View", "Search"],
      mcp_config: %{
        "postgres" => %{
          "command" => "npx",
          "args" => ["@modelcontextprotocol/server-postgres", System.get_env("DATABASE_URL")]
        }
      }
    ]
  end
end
```

## Benefits of This Approach

1. **Leverages Elixir's Strengths** - Uses OTP, supervision, and message passing
2. **No Framework Lock-in** - Users can compose agents however they need
3. **Gradual Adoption** - Start with simple patterns, evolve as needed
4. **Fault Tolerance** - Built on supervised processes
5. **Scalability** - Agents can run distributed across nodes
6. **Testability** - Each agent is an isolated process

## Anti-Patterns to Avoid

1. **Over-Engineering** - Don't build complex frameworks users don't need
2. **Tight Coupling** - Keep agents loosely coupled via messages
3. **Shared Mutable State** - Use process state, not ETS/databases
4. **Blocking Operations** - Use async patterns and timeouts
5. **Magic Abstractions** - Keep it simple and explicit

## Conclusion

The ClaudeCode SDK should enable agent workflows through:

1. **Education** - Documentation and examples showing agent patterns
2. **Composition** - Tools for combining agents (coordinators, pipelines)
3. **Integration** - Bridges to Phoenix, Broadway, and other Elixir tools
4. **Flexibility** - Let users build the agent systems they need

By focusing on composable patterns rather than frameworks, we give users the power to build sophisticated agent systems while keeping the SDK simple and maintainable.