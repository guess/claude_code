defmodule ClaudeCode.Message.FilesPersistedEvent do
  @moduledoc """
  Represents a files persisted event from the Claude CLI.

  Emitted when files have been persisted during a session, containing
  metadata about each file that was saved.

  ## Fields

  - `:files` - List of maps with `:filename` and `:file_id` keys
  - `:failed` - List of maps with `:filename` and `:error` keys for files that failed to persist
  - `:processed_at` - ISO 8601 timestamp when files were processed
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "files_persisted",
    "files": [
      {"filename": "example.ex", "file_id": "file-abc123"}
    ],
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  @enforce_keys [:type, :subtype, :session_id]
  defstruct [
    :type,
    :subtype,
    :uuid,
    :session_id,
    :processed_at,
    files: [],
    failed: []
  ]

  @type file_entry :: %{filename: String.t(), file_id: String.t()}
  @type failed_entry :: %{filename: String.t(), error: String.t()}

  @type t :: %__MODULE__{
          type: :system,
          subtype: :files_persisted,
          files: [file_entry()],
          failed: [failed_entry()],
          processed_at: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new FilesPersistedEvent from JSON data.

  ## Examples

      iex> FilesPersistedEvent.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "files_persisted",
      ...>   "files" => [%{"filename" => "test.ex", "file_id" => "file-1"}],
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %FilesPersistedEvent{type: :system, subtype: :files_persisted, ...}}

      iex> FilesPersistedEvent.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "files_persisted", "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :files_persisted,
       files: parse_files(json["files"]),
       failed: parse_failed(json["failed"]),
       processed_at: json["processedAt"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "files_persisted"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a FilesPersistedEvent.
  """
  @spec files_persisted_event?(any()) :: boolean()
  def files_persisted_event?(%__MODULE__{type: :system, subtype: :files_persisted}), do: true
  def files_persisted_event?(_), do: false

  defp parse_files(files) when is_list(files) do
    Enum.flat_map(files, fn
      %{"filename" => filename, "file_id" => file_id} ->
        [%{filename: filename, file_id: file_id}]

      _ ->
        []
    end)
  end

  defp parse_files(_), do: []

  defp parse_failed(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{"filename" => filename, "error" => error} ->
        [%{filename: filename, error: error}]

      _ ->
        []
    end)
  end

  defp parse_failed(_), do: []
end

defimpl Jason.Encoder, for: ClaudeCode.Message.FilesPersistedEvent do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.FilesPersistedEvent do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
