defmodule ClaudeCode.SlashCommand do
  @moduledoc """
  Information about an available skill (invoked via /command syntax).

  Returned as part of the initialization response from the CLI.

  ## Fields

    * `:name` - Skill name (without the leading slash)
    * `:description` - Description of what the skill does
    * `:argument_hint` - Hint for skill arguments (e.g., `"<file>"`)
  """

  defstruct [
    :name,
    :description,
    :argument_hint
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          argument_hint: String.t() | nil
        }

  @doc """
  Creates a SlashCommand from a JSON map.

  ## Examples

      iex> ClaudeCode.SlashCommand.new(%{"name" => "commit", "description" => "Create a commit", "argumentHint" => "<message>"})
      %ClaudeCode.SlashCommand{name: "commit", description: "Create a commit", argument_hint: "<message>"}

  """
  @spec new(map() | String.t()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      name: data["name"],
      description: data["description"],
      argument_hint: data["argumentHint"]
    }
  end

  def new(name) when is_binary(name) do
    %__MODULE__{name: name, description: nil, argument_hint: nil}
  end
end

defimpl Jason.Encoder, for: ClaudeCode.SlashCommand do
  def encode(cmd, opts) do
    cmd
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.SlashCommand do
  def encode(cmd, encoder) do
    cmd
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
