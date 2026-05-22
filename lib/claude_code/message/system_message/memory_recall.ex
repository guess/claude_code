defmodule ClaudeCode.Message.SystemMessage.MemoryRecall do
  @moduledoc """
  Represents a memory recall system message from the Claude CLI.

  Emitted when the CLI recalls memories for the session, containing
  the recall mode and a list of matched memory entries.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:memory_recall`
  - `:mode` - Recall mode atom (`:select` or `:synthesize`)
  - `:memories` - List of memory entry maps with `:path`, `:scope`, and optional `:body` keys
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "memory_recall",
    "mode": "select",
    "memories": [
      {"path": "/path/to/memory.md", "scope": "personal", "body": "Memory content..."}
    ],
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id, :memories]
  defstruct [
    :type,
    :subtype,
    :mode,
    :memories,
    :uuid,
    :session_id
  ]

  @type memory_entry :: %{path: String.t(), scope: :personal | :team | :organization | nil, body: String.t() | nil}

  @type t :: %__MODULE__{
          type: :system,
          subtype: :memory_recall,
          mode: :select | :synthesize | nil,
          memories: [memory_entry()],
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new MemoryRecall from JSON data.

  The `"mode"` string is parsed to an atom (`:select` or `:synthesize`).
  Each memory's `"scope"` is parsed to an atom (`:personal`, `:team`, or `:organization`).
  Unknown values are parsed to `nil`.

  ## Examples

      iex> MemoryRecall.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "memory_recall",
      ...>   "mode" => "select",
      ...>   "memories" => [%{"path" => "/path/to/mem.md", "scope" => "personal"}],
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %MemoryRecall{type: :system, subtype: :memory_recall, mode: :select, ...}}

      iex> MemoryRecall.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "memory_recall", "memories" => memories, "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :memory_recall,
       mode: parse_mode(json["mode"]),
       memories: parse_memories(memories),
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "memory_recall"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a MemoryRecall.
  """
  @spec memory_recall?(any()) :: boolean()
  def memory_recall?(%__MODULE__{type: :system, subtype: :memory_recall}), do: true
  def memory_recall?(_), do: false

  defp parse_mode("select"), do: :select
  defp parse_mode("synthesize"), do: :synthesize
  defp parse_mode(_), do: nil

  defp parse_memories(memories) when is_list(memories) do
    Enum.map(memories, fn entry ->
      %{
        path: entry["path"],
        scope: parse_scope(entry["scope"]),
        body: entry["body"]
      }
    end)
  end

  defp parse_memories(_), do: []

  defp parse_scope("personal"), do: :personal
  defp parse_scope("team"), do: :team
  defp parse_scope("organization"), do: :organization
  defp parse_scope(_), do: nil
end
