defmodule ClaudeCode.Message.PartialAssistantMessage do
  @moduledoc """
  Represents a partial assistant message from the Claude CLI when using partial message streaming.

  Partial assistant messages are emitted when `include_partial_messages: true` is enabled.
  They provide real-time updates as Claude generates responses, enabling
  character-by-character streaming for LiveView applications.

  This type corresponds to `SDKPartialAssistantMessage` in the TypeScript SDK.

  ## Event Types

  - `message_start` - Signals the beginning of a new message
  - `content_block_start` - Signals the beginning of a new content block (text or tool_use)
  - `content_block_delta` - Contains incremental content updates (text chunks, tool input JSON, signatures, citations)
  - `content_block_stop` - Signals the end of a content block
  - `message_delta` - Contains message-level updates (stop_reason, usage)
  - `message_stop` - Signals the end of the message

  ## Example Usage

      ClaudeCode.query_stream(session, "Hello", include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(&IO.write/1)

  ## JSON Format

  ```json
  {
    "type": "stream_event",
    "event": {
      "type": "content_block_delta",
      "index": 0,
      "delta": {"type": "text_delta", "text": "Hello"}
    },
    "session_id": "...",
    "parent_tool_use_id": null,
    "uuid": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Content
  alias ClaudeCode.Message
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Usage

  @enforce_keys [:type, :event, :session_id]
  defstruct [
    :type,
    :event,
    :session_id,
    :parent_tool_use_id,
    :uuid
  ]

  @type event_type ::
          :message_start
          | :content_block_start
          | :content_block_delta
          | :content_block_stop
          | :message_delta
          | :message_stop

  @type event ::
          %{type: event_type()}
          | %{type: :content_block_start, index: non_neg_integer(), content_block: Content.t()}
          | %{type: :content_block_delta, index: non_neg_integer(), delta: Content.delta()}
          | %{type: :content_block_stop, index: non_neg_integer()}
          | %{type: :message_start, message: AssistantMessage.message()}
          | %{type: :message_delta, delta: Message.delta() | nil, usage: Usage.t()}
          | %{type: :message_stop}

  @type t :: %__MODULE__{
          type: :stream_event,
          event: event(),
          session_id: String.t(),
          parent_tool_use_id: String.t() | nil,
          uuid: String.t() | nil
        }

  @doc """
  Creates a new PartialAssistantMessage from JSON data.

  ## Examples

      iex> PartialAssistantMessage.new(%{
      ...>   "type" => "stream_event",
      ...>   "event" => %{"type" => "content_block_delta", "index" => 0, "delta" => %{"type" => "text_delta", "text" => "Hi"}},
      ...>   "session_id" => "abc123"
      ...> })
      {:ok, %PartialAssistantMessage{type: :stream_event, event: %{type: :content_block_delta, ...}, ...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | tuple()}
  def new(%{"type" => "stream_event"} = json) do
    case json do
      %{"event" => event_data, "session_id" => session_id} ->
        case parse_event(event_data) do
          nil ->
            {:error, :unknown_event_type}

          event ->
            {:ok,
             %__MODULE__{
               type: :stream_event,
               event: event,
               session_id: session_id,
               parent_tool_use_id: json["parent_tool_use_id"],
               uuid: json["uuid"]
             }}
        end

      %{"event" => _event_data} ->
        {:error, :missing_session_id}

      _ ->
        {:error, :missing_event}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Checks if this partial message is a text delta.
  """
  @spec text_delta?(t()) :: boolean()
  def text_delta?(%__MODULE__{event: %{type: :content_block_delta, delta: %{type: :text_delta}}}), do: true
  def text_delta?(_), do: false

  @doc """
  Extracts text from a text_delta in a single match.

  Returns `{:ok, text}` for text deltas, `:error` otherwise.
  """
  @spec extract_text(t()) :: {:ok, String.t()} | :error
  def extract_text(%__MODULE__{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}}),
    do: {:ok, text}

  def extract_text(_), do: :error

  @doc """
  Extracts thinking from a thinking_delta in a single match.

  Returns `{:ok, thinking}` for thinking deltas, `:error` otherwise.
  """
  @spec extract_thinking(t()) :: {:ok, String.t()} | :error
  def extract_thinking(%__MODULE__{
        event: %{type: :content_block_delta, delta: %{type: :thinking_delta, thinking: thinking}}
      }),
      do: {:ok, thinking}

  def extract_thinking(_), do: :error

  # Private functions

  # Event-type dispatch: each event type only extracts the fields it needs,
  # avoiding the overhead of running 6 maybe_add_* no-ops per event.

  defp parse_event(%{"type" => "content_block_delta", "index" => index, "delta" => delta}) do
    case Content.parse_delta(delta) do
      {:ok, parsed} -> %{type: :content_block_delta, index: index, delta: parsed}
      {:error, _} -> nil
    end
  end

  defp parse_event(%{"type" => "content_block_start", "index" => index, "content_block" => block}) do
    case parse_content_block(block) do
      nil -> nil
      parsed -> %{type: :content_block_start, index: index, content_block: parsed}
    end
  end

  defp parse_event(%{"type" => "content_block_stop", "index" => index}) do
    %{type: :content_block_stop, index: index}
  end

  defp parse_event(%{"type" => "message_start", "message" => message}) do
    case AssistantMessage.parse_api_message(message) do
      {:ok, parsed} -> %{type: :message_start, message: parsed}
      {:error, _} -> nil
    end
  end

  defp parse_event(%{"type" => "message_delta"} = data) do
    event = %{
      type: :message_delta,
      delta: ClaudeCode.Message.parse_delta(data["delta"]),
      usage: ClaudeCode.Usage.parse(data["usage"])
    }

    maybe_add_field(event, :context_management, data["context_management"])
  end

  defp parse_event(%{"type" => "message_stop"}) do
    %{type: :message_stop}
  end

  defp parse_event(_), do: nil

  defp maybe_add_field(event, _key, nil), do: event
  defp maybe_add_field(event, key, value), do: Map.put(event, key, value)

  # Delegates to CLI.Parser.parse_content/1 for types that have content modules
  # (text, tool_use, thinking, etc.). Returns nil for unknown types.
  defp parse_content_block(block) when is_map(block) do
    case Parser.parse_content(block) do
      {:ok, struct} -> struct
      {:error, _} -> nil
    end
  end
end

defimpl String.Chars, for: ClaudeCode.Message.PartialAssistantMessage do
  def to_string(%{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}}), do: text

  def to_string(_), do: ""
end
