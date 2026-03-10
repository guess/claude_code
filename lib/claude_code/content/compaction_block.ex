defmodule ClaudeCode.Content.CompactionBlock do
  @moduledoc """
  Represents a compaction content block within a Claude message.

  Compaction blocks contain a summary of previously compacted context.
  They appear when the API's autocompact context management strategy
  is triggered. The content may be nil if compaction failed.
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type]
  defstruct [:type, :content]

  @type t :: %__MODULE__{
          type: :compaction,
          content: String.t() | nil
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "compaction"} = data) do
    {:ok, %__MODULE__{type: :compaction, content: data["content"]}}
  end

  def new(_), do: {:error, :invalid_content_type}
end

defimpl String.Chars, for: ClaudeCode.Content.CompactionBlock do
  def to_string(%{content: nil}), do: "[compaction failed]"
  def to_string(%{content: content}), do: content
end
