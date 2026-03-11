defmodule ClaudeCode.Model.Info do
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
    * `:supports_auto_mode` - Whether this model supports auto mode (optional)
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.Model.Effort

  defstruct [
    :value,
    :display_name,
    :description,
    supports_effort: false,
    supported_effort_levels: [],
    supports_adaptive_thinking: false,
    supports_fast_mode: false,
    supports_auto_mode: false
  ]

  @type t :: %__MODULE__{
          value: String.t(),
          display_name: String.t(),
          description: String.t(),
          supports_effort: boolean(),
          supported_effort_levels: [Effort.t()],
          supports_adaptive_thinking: boolean(),
          supports_fast_mode: boolean(),
          supports_auto_mode: boolean()
        }

  @doc """
  Creates a Model.Info from a JSON map.

  ## Examples

      iex> ClaudeCode.Model.Info.new(%{"value" => "claude-sonnet-4-6", "displayName" => "Claude Sonnet 4.6", "description" => "Fast model"})
      %ClaudeCode.Model.Info{value: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6", description: "Fast model", supports_effort: false, supported_effort_levels: [], supports_adaptive_thinking: false, supports_fast_mode: false}

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
      supports_fast_mode: data["supports_fast_mode"] || false,
      supports_auto_mode: data["supports_auto_mode"] || false
    }
  end

  defp parse_effort_levels(nil), do: []
  defp parse_effort_levels(list) when is_list(list), do: Enum.map(list, &Effort.parse/1)
end
