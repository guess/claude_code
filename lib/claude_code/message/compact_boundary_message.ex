defmodule ClaudeCode.Message.CompactBoundaryMessage do
  @moduledoc """
  Represents a conversation compaction boundary message from the Claude CLI.

  Compact boundary messages indicate that the CLI has compacted the conversation
  history to reduce token usage. This message provides metadata about the compaction.

  Matches the official SDK schema:
  ```
  {
    type: "system",
    subtype: "compact_boundary",
    uuid: string,
    session_id: string,
    compact_metadata: {
      trigger: "manual" | "auto",
      pre_tokens: number
    }
  }
  ```
  """

  alias ClaudeCode.Types

  @enforce_keys [
    :type,
    :subtype,
    :uuid,
    :session_id,
    :compact_metadata
  ]
  defstruct [
    :type,
    :subtype,
    :uuid,
    :session_id,
    :compact_metadata
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :compact_boundary,
          uuid: String.t(),
          session_id: Types.session_id(),
          compact_metadata: %{
            trigger: String.t(),
            pre_tokens: non_neg_integer()
          }
        }

  @doc """
  Creates a new CompactBoundaryMessage from JSON data.

  ## Examples

      iex> CompactBoundaryMessage.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "compact_boundary",
      ...>   "uuid" => "...",
      ...>   "session_id" => "...",
      ...>   "compact_metadata" => %{"trigger" => "auto", "pre_tokens" => 5000}
      ...> })
      {:ok, %CompactBoundaryMessage{...}}

      iex> CompactBoundaryMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, :invalid_message_type | {:missing_fields, [atom()]}}
  def new(%{"type" => "system", "subtype" => "compact_boundary"} = json) do
    required_fields = [
      "subtype",
      "uuid",
      "session_id",
      "compact_metadata"
    ]

    missing = Enum.filter(required_fields, &(not Map.has_key?(json, &1)))

    if Enum.empty?(missing) do
      message = %__MODULE__{
        type: :system,
        subtype: :compact_boundary,
        uuid: json["uuid"],
        session_id: json["session_id"],
        compact_metadata: parse_compact_metadata(json["compact_metadata"])
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a CompactBoundaryMessage.
  """
  @spec compact_boundary_message?(any()) :: boolean()
  def compact_boundary_message?(%__MODULE__{type: :system, subtype: :compact_boundary}), do: true
  def compact_boundary_message?(_), do: false

  defp parse_compact_metadata(metadata) when is_map(metadata) do
    %{
      trigger: metadata["trigger"],
      pre_tokens: metadata["pre_tokens"] || 0
    }
  end

  defp parse_compact_metadata(_), do: nil
end

defimpl Jason.Encoder, for: ClaudeCode.Message.CompactBoundaryMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.CompactBoundaryMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
