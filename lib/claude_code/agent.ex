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
        tools: ["View", "Grep", "Glob"],
        model: "sonnet"
      )

      planner = ClaudeCode.Agent.new(
        name: "architect",
        description: "Software architect",
        prompt: "You design system architectures."
      )

      {:ok, session} = ClaudeCode.start_link(agents: [reviewer, planner])

      # Raw maps still work too
      {:ok, session} = ClaudeCode.start_link(agents: %{
        "code-reviewer" => %{"description" => "Expert code reviewer", ...}
      })

  """

  @enforce_keys [:name]
  defstruct [:name, :description, :prompt, :model, :tools]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          prompt: String.t() | nil,
          model: String.t() | nil,
          tools: [String.t()] | nil
        }

  @doc """
  Creates a new Agent struct.

  ## Options

    * `:name` - (required) Agent name used as the identifier
    * `:description` - What the agent does (shown to Claude for dispatch)
    * `:prompt` - System prompt for the agent
    * `:model` - Model to use (e.g. `"sonnet"`, `"haiku"`, `"opus"`)
    * `:tools` - List of tool names the agent can access

  ## Examples

      iex> ClaudeCode.Agent.new(name: "reviewer", prompt: "Review code.")
      %ClaudeCode.Agent{name: "reviewer", prompt: "Review code.", description: nil, model: nil, tools: nil}

      iex> ClaudeCode.Agent.new(name: "planner", description: "Plans work", prompt: "You plan.", model: "haiku", tools: ["View"])
      %ClaudeCode.Agent{name: "planner", description: "Plans work", prompt: "You plan.", model: "haiku", tools: ["View"]}

  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.get(opts, :description),
      prompt: Keyword.get(opts, :prompt),
      model: Keyword.get(opts, :model),
      tools: Keyword.get(opts, :tools)
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
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
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
