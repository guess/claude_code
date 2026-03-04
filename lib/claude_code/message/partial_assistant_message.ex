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
  - `content_block_delta` - Contains incremental content updates (text chunks, tool input JSON)
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

  @type delta ::
          %{type: :text_delta, text: String.t()}
          | %{type: :input_json_delta, partial_json: String.t()}
          | %{type: :thinking_delta, thinking: String.t()}
          | map()

  @type event ::
          %{type: event_type()}
          | %{type: :content_block_start, index: non_neg_integer(), content_block: map()}
          | %{type: :content_block_delta, index: non_neg_integer(), delta: delta()}
          | %{type: :content_block_stop, index: non_neg_integer()}
          | %{type: :message_start, message: map()}
          | %{type: :message_delta, delta: map(), usage: map()}
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
        {:ok,
         %__MODULE__{
           type: :stream_event,
           event: parse_event(event_data),
           session_id: session_id,
           parent_tool_use_id: json["parent_tool_use_id"],
           uuid: json["uuid"]
         }}

      %{"event" => _event_data} ->
        {:error, :missing_session_id}

      _ ->
        {:error, :missing_event}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a PartialAssistantMessage.
  """
  @spec partial_assistant_message?(any()) :: boolean()
  def partial_assistant_message?(%__MODULE__{type: :stream_event}), do: true
  def partial_assistant_message?(_), do: false

  @doc """
  Checks if this partial message is a text delta.
  """
  @spec text_delta?(t()) :: boolean()
  def text_delta?(%__MODULE__{event: %{type: :content_block_delta, delta: %{type: :text_delta}}}), do: true

  def text_delta?(_), do: false

  @doc """
  Extracts text from a text_delta event.

  Returns nil if not a text delta event.
  """
  @spec get_text(t()) :: String.t() | nil
  def get_text(%__MODULE__{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}}), do: text

  def get_text(_), do: nil

  @doc """
  Checks if this partial message is a thinking delta.
  """
  @spec thinking_delta?(t()) :: boolean()
  def thinking_delta?(%__MODULE__{event: %{type: :content_block_delta, delta: %{type: :thinking_delta}}}), do: true

  def thinking_delta?(_), do: false

  @doc """
  Extracts thinking from a thinking_delta event.

  Returns nil if not a thinking delta event.
  """
  @spec get_thinking(t()) :: String.t() | nil
  def get_thinking(%__MODULE__{event: %{type: :content_block_delta, delta: %{type: :thinking_delta, thinking: thinking}}}),
    do: thinking

  def get_thinking(_), do: nil

  @doc """
  Checks if this partial message is an input JSON delta (for tool use).
  """
  @spec input_json_delta?(t()) :: boolean()
  def input_json_delta?(%__MODULE__{event: %{type: :content_block_delta, delta: %{type: :input_json_delta}}}), do: true

  def input_json_delta?(_), do: false

  @doc """
  Extracts partial JSON from an input_json_delta event.

  Returns nil if not an input_json_delta event.
  """
  @spec get_partial_json(t()) :: String.t() | nil
  def get_partial_json(%__MODULE__{
        event: %{type: :content_block_delta, delta: %{type: :input_json_delta, partial_json: json}}
      }),
      do: json

  def get_partial_json(_), do: nil

  @doc """
  Gets the content block index for delta events.

  Returns nil for non-content block events.
  """
  @spec get_index(t()) :: non_neg_integer() | nil
  def get_index(%__MODULE__{event: %{index: index}}), do: index
  def get_index(_), do: nil

  @doc """
  Gets the event type.
  """
  @spec event_type(t()) :: event_type()
  def event_type(%__MODULE__{event: %{type: type}}), do: type

  # Private functions

  @event_type_map %{
    "message_start" => :message_start,
    "content_block_start" => :content_block_start,
    "content_block_delta" => :content_block_delta,
    "content_block_stop" => :content_block_stop,
    "message_delta" => :message_delta,
    "message_stop" => :message_stop
  }

  @delta_type_map %{
    "text_delta" => :text_delta,
    "input_json_delta" => :input_json_delta,
    "thinking_delta" => :thinking_delta
  }

  @stop_reason_map %{
    "end_turn" => :end_turn,
    "max_tokens" => :max_tokens,
    "stop_sequence" => :stop_sequence,
    "tool_use" => :tool_use,
    "refusal" => :refusal
  }

  @known_message_keys [
    "id",
    "type",
    "role",
    "content",
    "model",
    "stop_reason",
    "stop_sequence",
    "usage",
    "context_management"
  ]

  @known_usage_key_map %{
    "input_tokens" => :input_tokens,
    "output_tokens" => :output_tokens,
    "cache_creation_input_tokens" => :cache_creation_input_tokens,
    "cache_read_input_tokens" => :cache_read_input_tokens,
    "cache_creation" => :cache_creation,
    "service_tier" => :service_tier,
    "inference_geo" => :inference_geo,
    "server_tool_use" => :server_tool_use,
    "iterations" => :iterations,
    "speed" => :speed
  }

  @known_context_management_key_map %{
    "mode" => :mode,
    "compacted" => :compacted,
    "truncated_message_ids" => :truncated_message_ids,
    "was_auto_truncated" => :was_auto_truncated
  }

  defp parse_event(%{"type" => type} = event_data) do
    base = %{type: parse_event_type(type)}

    base
    |> maybe_add_index(event_data)
    |> maybe_add_delta(event_data)
    |> maybe_add_content_block(event_data)
    |> maybe_add_message(event_data)
    |> maybe_add_usage(event_data)
    |> maybe_add_context_management(event_data)
  end

  defp parse_event_type(type) when is_binary(type) do
    case Map.fetch(@event_type_map, type) do
      {:ok, atom} ->
        atom

      :error ->
        String.to_atom(type)
    end
  end

  defp parse_event_type(other), do: other

  defp maybe_add_index(event, %{"index" => index}), do: Map.put(event, :index, index)
  defp maybe_add_index(event, _), do: event

  defp maybe_add_delta(event, %{"delta" => delta_data}) do
    Map.put(event, :delta, parse_delta(delta_data))
  end

  defp maybe_add_delta(event, _), do: event

  defp maybe_add_content_block(event, %{"content_block" => block}) do
    Map.put(event, :content_block, parse_content_block(block))
  end

  defp maybe_add_content_block(event, _), do: event

  defp maybe_add_message(event, %{"message" => message}) do
    Map.put(event, :message, parse_message_data(message))
  end

  defp maybe_add_message(event, _), do: event

  defp maybe_add_usage(event, %{"usage" => usage}) do
    Map.put(event, :usage, parse_usage_data(usage))
  end

  defp maybe_add_usage(event, _), do: event

  defp maybe_add_context_management(event, %{"context_management" => cm}) when not is_nil(cm) do
    Map.put(event, :context_management, parse_context_management_data(cm))
  end

  defp maybe_add_context_management(event, _), do: event

  defp parse_message_data(message) when is_map(message) do
    message
    |> Map.drop(@known_message_keys)
    |> maybe_put_known_field(message, "id", :id, & &1)
    |> maybe_put_known_field(message, "type", :type, &parse_message_type/1)
    |> maybe_put_known_field(message, "role", :role, &parse_role/1)
    |> maybe_put_known_field(message, "content", :content, & &1)
    |> maybe_put_known_field(message, "model", :model, & &1)
    |> maybe_put_known_field(message, "stop_reason", :stop_reason, &parse_stop_reason/1)
    |> maybe_put_known_field(message, "stop_sequence", :stop_sequence, & &1)
    |> maybe_put_known_field(message, "usage", :usage, &parse_usage_data/1)
    |> maybe_put_known_field(message, "context_management", :context_management, &parse_context_management_data/1)
  end

  defp parse_message_data(other), do: other

  defp parse_usage_data(usage) when is_map(usage) do
    Map.new(usage, fn
      {key, value} when is_binary(key) -> {Map.get(@known_usage_key_map, key, key), value}
      {key, value} -> {key, value}
    end)
  end

  defp parse_usage_data(other), do: other

  defp parse_context_management_data(cm) when is_map(cm) do
    Map.new(cm, fn
      {key, value} when is_binary(key) -> {Map.get(@known_context_management_key_map, key, key), value}
      {key, value} -> {key, value}
    end)
  end

  defp parse_context_management_data(other), do: other

  defp parse_message_type("message"), do: :message
  defp parse_message_type(other), do: other

  defp parse_role("assistant"), do: :assistant
  defp parse_role("user"), do: :user
  defp parse_role(other), do: other

  defp parse_stop_reason(nil), do: nil

  defp parse_stop_reason(reason) when is_binary(reason) do
    case Map.fetch(@stop_reason_map, reason) do
      {:ok, atom} ->
        atom

      :error ->
        String.to_atom(reason)
    end
  end

  defp parse_stop_reason(reason), do: reason

  defp parse_delta(%{"type" => "text_delta", "text" => text}) do
    %{type: :text_delta, text: text}
  end

  defp parse_delta(%{"type" => "input_json_delta", "partial_json" => json}) do
    %{type: :input_json_delta, partial_json: json}
  end

  defp parse_delta(%{"type" => "thinking_delta", "thinking" => thinking}) do
    %{type: :thinking_delta, thinking: thinking}
  end

  defp parse_delta(%{"type" => type} = delta) do
    delta
    |> Map.delete("type")
    |> Map.put(:type, Map.get(@delta_type_map, type, type))
  end

  defp parse_delta(delta) when is_map(delta), do: delta

  defp parse_content_block(%{"type" => "text"} = block) do
    %{type: :text, text: block["text"] || ""}
  end

  defp parse_content_block(%{"type" => "tool_use"} = block) do
    %{
      type: :tool_use,
      id: block["id"],
      name: block["name"],
      input: block["input"] || %{}
    }
  end

  defp parse_content_block(%{"type" => type} = block) do
    block
    |> Map.delete("type")
    |> Map.put(:type, type)
  end

  defp maybe_put_known_field(acc, source, source_key, target_key, parser) do
    if Map.has_key?(source, source_key) do
      Map.put(acc, target_key, parser.(source[source_key]))
    else
      acc
    end
  end
end

defimpl String.Chars, for: ClaudeCode.Message.PartialAssistantMessage do
  def to_string(%{event: %{type: :content_block_delta, delta: %{type: :text_delta, text: text}}}), do: text

  def to_string(_), do: ""
end

defimpl Jason.Encoder, for: ClaudeCode.Message.PartialAssistantMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.PartialAssistantMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
