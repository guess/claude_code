defmodule ClaudeCode.Message.SystemMessage.Generic do
  @moduledoc """
  Fallback struct for system messages whose `subtype` this SDK version does not
  model with a dedicated struct (e.g. a `thinking_tokens` message emitted by a
  newer CLI).

  Rather than failing to parse — and dropping the message — the parser returns a
  `Generic` so consumers still receive the event with its full payload. This
  keeps the SDK forward-compatible with new CLI system-message subtypes without a
  release. When a subtype becomes common enough to warrant typed access, promote
  it to its own module under `ClaudeCode.Message.SystemMessage.*` and register it
  in `ClaudeCode.CLI.Parser`.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - The raw subtype string (kept as a string, not an atom, since the
    set of future subtypes is open-ended)
  - `:session_id` - Session identifier, when present
  - `:uuid` - Message UUID, when present
  - `:data` - The remaining message fields (everything except `type`, `subtype`,
    `session_id`, and `uuid`), with keys normalized to snake_case

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "thinking_tokens",
    "session_id": "...",
    "uuid": "...",
    "...": "subtype-specific fields"
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @reserved_keys ~w(type subtype session_id uuid)

  @enforce_keys [:type, :subtype]
  defstruct [:type, :subtype, :session_id, :uuid, data: %{}]

  @type t :: %__MODULE__{
          type: :system,
          subtype: String.t(),
          session_id: String.t() | nil,
          uuid: String.t() | nil,
          data: map()
        }

  @doc """
  Creates a new `Generic` system message from JSON data.

  Expects keys to already be normalized (see `ClaudeCode.CLI.Parser.normalize_keys/1`).

  ## Examples

      iex> Generic.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "thinking_tokens",
      ...>   "session_id" => "session-1",
      ...>   "max_thinking_tokens" => 10_000
      ...> })
      {:ok,
       %Generic{
         type: :system,
         subtype: "thinking_tokens",
         session_id: "session-1",
         uuid: nil,
         data: %{"max_thinking_tokens" => 10_000}
       }}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => subtype} = json) when is_binary(subtype) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: subtype,
       session_id: json["session_id"],
       uuid: json["uuid"],
       data: Map.drop(json, @reserved_keys)
     }}
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a `Generic` system message.
  """
  @spec generic?(any()) :: boolean()
  def generic?(%__MODULE__{type: :system}), do: true
  def generic?(_), do: false
end
