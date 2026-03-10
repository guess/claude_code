defmodule ClaudeCode.AgentInfo do
  @moduledoc """
  Information about an available subagent.

  Returned as part of the initialization response from the CLI,
  describing agents that can be invoked via the Task tool.

  ## Fields

    * `:name` - Agent type identifier (e.g., "Explore")
    * `:description` - Description of when to use this agent
    * `:model` - Model alias this agent uses (nil if it inherits the parent's model)
  """

  use ClaudeCode.JSONEncoder

  defstruct [
    :name,
    :description,
    :model
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          model: String.t() | nil
        }

  @doc """
  Creates an AgentInfo from a JSON map.

  ## Examples

      iex> ClaudeCode.AgentInfo.new(%{"name" => "Explore", "description" => "Fast codebase exploration"})
      %ClaudeCode.AgentInfo{name: "Explore", description: "Fast codebase exploration", model: nil}

  """
  @spec new(map()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      name: data["name"],
      description: data["description"],
      model: data["model"]
    }
  end
end
