defmodule ClaudeCode.Content.RedactedThinkingBlock do
  @moduledoc """
  Represents a redacted thinking content block within a Claude message.

  Redacted thinking blocks contain encrypted thinking data that cannot
  be displayed to the user. They appear when Claude's reasoning is
  filtered by streaming classifiers.
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :data]
  defstruct [:type, :data]

  @type t :: %__MODULE__{
          type: :redacted_thinking,
          data: String.t()
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "redacted_thinking"} = data) do
    required = ["data"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      {:ok, %__MODULE__{type: :redacted_thinking, data: data["data"]}}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}
end

defimpl String.Chars, for: ClaudeCode.Content.RedactedThinkingBlock do
  def to_string(_), do: "[redacted thinking]"
end
