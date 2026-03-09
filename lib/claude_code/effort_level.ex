defmodule ClaudeCode.EffortLevel do
  @moduledoc """
  Effort level for controlling how much effort Claude puts into its response.

  Used by `ClaudeCode.ModelInfo` to describe supported effort levels and by
  session/query options to configure the effort level.

  ## Values

    * `:low` - Minimal thinking, fastest responses
    * `:medium` - Moderate thinking
    * `:high` - Deep reasoning (default)
    * `:max` - Maximum effort
  """

  @type t :: :low | :medium | :high | :max

  @doc """
  Parses an effort level string from the CLI into an atom.

  Returns the original value if unrecognized.

  ## Examples

      iex> ClaudeCode.EffortLevel.parse("low")
      :low

      iex> ClaudeCode.EffortLevel.parse("max")
      :max

  """
  @spec parse(String.t()) :: t()
  def parse("low"), do: :low
  def parse("medium"), do: :medium
  def parse("high"), do: :high
  def parse("max"), do: :max
  def parse(other), do: other
end
