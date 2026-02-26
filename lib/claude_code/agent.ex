defmodule ClaudeCode.Agent do
  @moduledoc """
  Struct and builder for custom subagent configurations.

  Provides a structured alternative to raw maps when configuring the `:agents`
  option for sessions and queries.

  ## Examples

      # Build agents with the struct builder
      reviewer = ClaudeCode.Agent.new(
        name: "code-reviewer",
        description: "Expert code reviewer",
        prompt: "You review code for quality and best practices.",
        tools: ["Read", "Grep", "Glob"],
        disallowed_tools: ["Write", "Edit"],
        model: "sonnet",
        permission_mode: :plan
      )

      planner = ClaudeCode.Agent.new(
        name: "architect",
        description: "Software architect",
        prompt: "You design system architectures.",
        max_turns: 10,
        memory: :project
      )

      {:ok, session} = ClaudeCode.start_link(agents: [reviewer, planner])

      # Raw maps still work too
      {:ok, session} = ClaudeCode.start_link(agents: %{
        "code-reviewer" => %{"description" => "Expert code reviewer", ...}
      })

  """

  @enforce_keys [:name]
  defstruct [
    :name,
    :description,
    :prompt,
    :model,
    :tools,
    :disallowed_tools,
    :permission_mode,
    :max_turns,
    :skills,
    :mcp_servers,
    :hooks,
    :memory,
    :background,
    :isolation
  ]

  @type memory_scope :: :user | :project | :local

  @type isolation_mode :: :worktree

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          prompt: String.t() | nil,
          model: String.t() | nil,
          tools: [String.t()] | nil,
          disallowed_tools: [String.t()] | nil,
          permission_mode: ClaudeCode.Types.permission_mode() | nil,
          max_turns: pos_integer() | nil,
          skills: [String.t()] | nil,
          mcp_servers: map() | nil,
          hooks: map() | nil,
          memory: memory_scope() | nil,
          background: boolean() | nil,
          isolation: isolation_mode() | nil
        }

  @doc """
  Creates a new Agent struct.

  ## Options

    * `:name` - (required) Agent name used as the identifier
    * `:description` - What the agent does (shown to Claude for dispatch)
    * `:prompt` - System prompt for the agent
    * `:model` - Model to use (e.g. `"sonnet"`, `"haiku"`, `"opus"`, `"inherit"`)
    * `:tools` - List of tool names the agent can access
    * `:disallowed_tools` - Tools to deny, removed from inherited or specified list
    * `:permission_mode` - Permission mode (`:default`, `:accept_edits`, `:dont_ask`, `:bypass_permissions`, `:delegate`, `:plan`)
    * `:max_turns` - Maximum number of agentic turns before the agent stops
    * `:skills` - Skills to load into the agent's context at startup
    * `:mcp_servers` - MCP servers available to this agent (map of server configs)
    * `:hooks` - Lifecycle hooks scoped to this agent (map of hook configs)
    * `:memory` - Persistent memory scope (`:user`, `:project`, or `:local`)
    * `:background` - Set to `true` to always run as a background task
    * `:isolation` - Set to `:worktree` to run in a temporary git worktree

  ## Examples

      iex> ClaudeCode.Agent.new(name: "reviewer", prompt: "Review code.")
      %ClaudeCode.Agent{name: "reviewer", prompt: "Review code.", description: nil, model: nil, tools: nil, disallowed_tools: nil, permission_mode: nil, max_turns: nil, skills: nil, mcp_servers: nil, hooks: nil, memory: nil, background: nil, isolation: nil}

      iex> ClaudeCode.Agent.new(name: "planner", description: "Plans work", prompt: "You plan.", model: "haiku", tools: ["View"])
      %ClaudeCode.Agent{name: "planner", description: "Plans work", prompt: "You plan.", model: "haiku", tools: ["View"], disallowed_tools: nil, permission_mode: nil, max_turns: nil, skills: nil, mcp_servers: nil, hooks: nil, memory: nil, background: nil, isolation: nil}

  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.get(opts, :description),
      prompt: Keyword.get(opts, :prompt),
      model: Keyword.get(opts, :model),
      tools: Keyword.get(opts, :tools),
      disallowed_tools: Keyword.get(opts, :disallowed_tools),
      permission_mode: Keyword.get(opts, :permission_mode),
      max_turns: Keyword.get(opts, :max_turns),
      skills: Keyword.get(opts, :skills),
      mcp_servers: Keyword.get(opts, :mcp_servers),
      hooks: Keyword.get(opts, :hooks),
      memory: Keyword.get(opts, :memory),
      background: Keyword.get(opts, :background),
      isolation: Keyword.get(opts, :isolation)
    }
  end

  @doc """
  Converts a list of Agent structs to the map format expected by the CLI.

  Returns `%{name => %{"description" => ..., "prompt" => ..., ...}}`.

  ## Examples

      iex> agents = [ClaudeCode.Agent.new(name: "reviewer", prompt: "Review code.", model: "haiku")]
      iex> ClaudeCode.Agent.to_agents_map(agents)
      %{"reviewer" => %{"prompt" => "Review code.", "model" => "haiku"}}

  """
  @spec to_agents_map([t()]) :: %{String.t() => %{String.t() => any()}}
  def to_agents_map(agents) when is_list(agents) do
    Map.new(agents, fn %__MODULE__{name: name} = agent ->
      config =
        %{}
        |> maybe_put("description", agent.description)
        |> maybe_put("prompt", agent.prompt)
        |> maybe_put("model", agent.model)
        |> maybe_put("tools", agent.tools)
        |> maybe_put("disallowedTools", agent.disallowed_tools)
        |> maybe_put_encoded("permissionMode", agent.permission_mode, &encode_permission_mode/1)
        |> maybe_put("maxTurns", agent.max_turns)
        |> maybe_put("skills", agent.skills)
        |> maybe_put("mcpServers", agent.mcp_servers)
        |> maybe_put("hooks", agent.hooks)
        |> maybe_put_encoded("memory", agent.memory, &encode_memory/1)
        |> maybe_put("background", agent.background)
        |> maybe_put_encoded("isolation", agent.isolation, &encode_isolation/1)

      {name, config}
    end)
  end

  @doc false
  def to_config_map(%__MODULE__{} = agent) do
    %{}
    |> maybe_put("name", agent.name)
    |> maybe_put("description", agent.description)
    |> maybe_put("prompt", agent.prompt)
    |> maybe_put("model", agent.model)
    |> maybe_put("tools", agent.tools)
    |> maybe_put("disallowedTools", agent.disallowed_tools)
    |> maybe_put_encoded("permissionMode", agent.permission_mode, &encode_permission_mode/1)
    |> maybe_put("maxTurns", agent.max_turns)
    |> maybe_put("skills", agent.skills)
    |> maybe_put("mcpServers", agent.mcp_servers)
    |> maybe_put("hooks", agent.hooks)
    |> maybe_put_encoded("memory", agent.memory, &encode_memory/1)
    |> maybe_put("background", agent.background)
    |> maybe_put_encoded("isolation", agent.isolation, &encode_isolation/1)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_encoded(map, _key, nil, _encoder), do: map
  defp maybe_put_encoded(map, key, value, encoder), do: Map.put(map, key, encoder.(value))

  # Atom-to-CLI-string conversions for enum fields

  defp encode_permission_mode(:default), do: "default"
  defp encode_permission_mode(:accept_edits), do: "acceptEdits"
  defp encode_permission_mode(:bypass_permissions), do: "bypassPermissions"
  defp encode_permission_mode(:delegate), do: "delegate"
  defp encode_permission_mode(:dont_ask), do: "dontAsk"
  defp encode_permission_mode(:plan), do: "plan"

  defp encode_memory(:user), do: "user"
  defp encode_memory(:project), do: "project"
  defp encode_memory(:local), do: "local"

  defp encode_isolation(:worktree), do: "worktree"
end

defimpl Jason.Encoder, for: ClaudeCode.Agent do
  def encode(agent, opts) do
    agent
    |> ClaudeCode.Agent.to_config_map()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Agent do
  def encode(agent, encoder) do
    agent
    |> ClaudeCode.Agent.to_config_map()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
