defmodule ClaudeCode.ModelInfo do
  @moduledoc """
  Information about an available model.

  Returned as part of the initialization response from the CLI.

  ## Fields

    * `:value` - Model identifier to use in API calls
    * `:display_name` - Human-readable display name
    * `:description` - Description of the model's capabilities
    * `:supports_effort` - Whether this model supports effort levels
    * `:supported_effort_levels` - Available effort levels (e.g., `[:low, :medium, :high]`)
    * `:supports_adaptive_thinking` - Whether this model supports adaptive thinking
    * `:supports_fast_mode` - Whether this model supports fast mode
  """

  use ClaudeCode.JSONEncoder

  defstruct [
    :value,
    :display_name,
    :description,
    supports_effort: false,
    supported_effort_levels: [],
    supports_adaptive_thinking: false,
    supports_fast_mode: false
  ]

  @type t :: %__MODULE__{
          value: String.t(),
          display_name: String.t(),
          description: String.t(),
          supports_effort: boolean(),
          supported_effort_levels: [ClaudeCode.EffortLevel.t()],
          supports_adaptive_thinking: boolean(),
          supports_fast_mode: boolean()
        }

  @doc """
  Creates a ModelInfo from a JSON map.

  ## Examples

      iex> ClaudeCode.ModelInfo.new(%{"value" => "claude-sonnet-4-6", "displayName" => "Claude Sonnet 4.6", "description" => "Fast model"})
      %ClaudeCode.ModelInfo{value: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6", description: "Fast model", supports_effort: false, supported_effort_levels: [], supports_adaptive_thinking: false, supports_fast_mode: false}

  """
  @spec new(map()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      value: data["value"],
      display_name: data["display_name"],
      description: data["description"],
      supports_effort: data["supports_effort"] || false,
      supported_effort_levels: parse_effort_levels(data["supported_effort_levels"]),
      supports_adaptive_thinking: data["supports_adaptive_thinking"] || false,
      supports_fast_mode: data["supports_fast_mode"] || false
    }
  end

  defp parse_effort_levels(nil), do: []
  defp parse_effort_levels(list) when is_list(list), do: Enum.map(list, &ClaudeCode.EffortLevel.parse/1)
end
