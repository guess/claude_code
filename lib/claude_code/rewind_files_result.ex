defmodule ClaudeCode.RewindFilesResult do
  @moduledoc """
  Result of a `ClaudeCode.rewind_files/2` operation.

  ## Fields

    * `:can_rewind` - Whether the rewind can be performed
    * `:error` - Error message if rewind cannot be performed
    * `:files_changed` - List of file paths that were changed
    * `:insertions` - Number of line insertions
    * `:deletions` - Number of line deletions
  """

  defstruct [
    :can_rewind,
    :error,
    :files_changed,
    :insertions,
    :deletions
  ]

  @type t :: %__MODULE__{
          can_rewind: boolean(),
          error: String.t() | nil,
          files_changed: [String.t()] | nil,
          insertions: non_neg_integer() | nil,
          deletions: non_neg_integer() | nil
        }

  @doc """
  Creates a RewindFilesResult from a JSON map.

  ## Examples

      iex> ClaudeCode.RewindFilesResult.new(%{"canRewind" => true, "filesChanged" => ["a.ex"], "insertions" => 5, "deletions" => 2})
      %ClaudeCode.RewindFilesResult{can_rewind: true, files_changed: ["a.ex"], insertions: 5, deletions: 2}

  """
  @spec new(map()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      can_rewind: data["canRewind"],
      error: data["error"],
      files_changed: data["filesChanged"],
      insertions: data["insertions"],
      deletions: data["deletions"]
    }
  end
end

defimpl Jason.Encoder, for: ClaudeCode.RewindFilesResult do
  def encode(result, opts) do
    result
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.RewindFilesResult do
  def encode(result, encoder) do
    result
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
