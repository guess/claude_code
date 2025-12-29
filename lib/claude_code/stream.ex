defmodule ClaudeCode.Stream do
  @moduledoc """
  Stream utilities for handling Claude Code responses.

  This module provides functions to create and manipulate streams of messages
  from Claude Code sessions. It enables real-time processing of Claude's
  responses without waiting for the complete result.

  ## Example

      session
      |> ClaudeCode.query("Write a story")
      |> ClaudeCode.Stream.text_content()
      |> Stream.each(&IO.write/1)
      |> Stream.run()
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Message
  alias ClaudeCode.Message.StreamEvent

  @doc """
  Creates a stream of messages from a Claude Code query.

  This is the primary function for creating message streams. It returns a
  Stream that emits messages as they arrive from the CLI.

  ## Options

    * `:timeout` - Maximum time to wait for each message (default: 60_000ms)
    * `:filter` - Message type filter (:all, :assistant, :tool_use, :result)

  ## Examples

      # Stream all messages
      ClaudeCode.Stream.create(session, "Hello")
      |> Enum.each(&IO.inspect/1)

      # Stream only assistant messages
      ClaudeCode.Stream.create(session, "Hello", filter: :assistant)
      |> Enum.map(& &1.message.content)
  """
  @spec create(pid(), String.t(), keyword()) :: Enumerable.t()
  def create(session, prompt, opts \\ []) do
    Stream.resource(
      fn ->
        # Defer initialization to avoid blocking on stream creation
        %{
          session: session,
          prompt: prompt,
          opts: opts,
          initialized: false,
          request_ref: nil,
          timeout: Keyword.get(opts, :timeout, 60_000),
          filter: Keyword.get(opts, :filter, :all),
          done: false
        }
      end,
      &next_message/1,
      &cleanup_stream/1
    )
  end

  @doc """
  Extracts text content from a message stream.

  Filters the stream to only emit text content from assistant messages,
  making it easy to collect the textual response.

  ## Examples

      text = session
      |> ClaudeCode.query("Tell me about Elixir")
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()
  """
  @spec text_content(Enumerable.t()) :: Enumerable.t()
  def text_content(stream) do
    stream
    |> Stream.filter(&match?(%Message.Assistant{}, &1))
    |> Stream.flat_map(fn %Message.Assistant{message: message} ->
      message.content
      |> Enum.filter(&match?(%Content.Text{}, &1))
      |> Enum.map(& &1.text)
    end)
  end

  @doc """
  Extracts text deltas from a partial message stream.

  This enables character-by-character streaming from Claude's responses.
  Use with `include_partial_messages: true` option.

  ## Examples

      # Real-time character streaming for LiveView
      ClaudeCode.query_stream(session, "Tell a story", include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(fn chunk ->
        Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:123", {:text_chunk, chunk})
      end)

      # Simple console output
      session
      |> ClaudeCode.query_stream("Hello", include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(&IO.write/1)
  """
  @spec text_deltas(Enumerable.t()) :: Enumerable.t()
  def text_deltas(stream) do
    stream
    |> Stream.filter(&StreamEvent.text_delta?/1)
    |> Stream.map(&StreamEvent.get_text/1)
  end

  @doc """
  Extracts all content deltas from a partial message stream.

  Returns a stream of delta maps, useful for tracking both text
  and tool use input as it arrives. Each element contains:
  - `type`: `:text_delta`, `:input_json_delta`, or `:thinking_delta`
  - `index`: The content block index
  - Content-specific fields (`text`, `partial_json`, or `thinking`)

  ## Examples

      ClaudeCode.query_stream(session, "Create a file", include_partial_messages: true)
      |> ClaudeCode.Stream.content_deltas()
      |> Enum.each(fn delta ->
        case delta.type do
          :text_delta -> IO.write(delta.text)
          :input_json_delta -> handle_tool_json(delta.partial_json)
          _ -> :ok
        end
      end)
  """
  @spec content_deltas(Enumerable.t()) :: Enumerable.t()
  def content_deltas(stream) do
    stream
    |> Stream.filter(&match?(%StreamEvent{event: %{type: :content_block_delta}}, &1))
    |> Stream.map(fn %StreamEvent{event: %{delta: delta, index: index}} ->
      Map.put(delta, :index, index)
    end)
  end

  @doc """
  Filters stream to only stream events of a specific event type.

  Valid event types: `:message_start`, `:content_block_start`,
  `:content_block_delta`, `:content_block_stop`, `:message_delta`, `:message_stop`

  ## Examples

      # Only content block deltas
      stream
      |> ClaudeCode.Stream.filter_event_type(:content_block_delta)
      |> Enum.each(&process_delta/1)
  """
  @spec filter_event_type(Enumerable.t(), StreamEvent.event_type()) :: Enumerable.t()
  def filter_event_type(stream, event_type) do
    Stream.filter(stream, fn
      %StreamEvent{event: %{type: ^event_type}} -> true
      _ -> false
    end)
  end

  @doc """
  Extracts tool use blocks from a message stream.

  Filters the stream to only emit tool use content blocks, making it easy
  to react to tool usage in real-time.

  ## Examples

      session
      |> ClaudeCode.query("Create some files")
      |> ClaudeCode.Stream.tool_uses()
      |> Enum.each(&handle_tool_use/1)
  """
  @spec tool_uses(Enumerable.t()) :: Enumerable.t()
  def tool_uses(stream) do
    stream
    |> Stream.filter(&match?(%Message.Assistant{}, &1))
    |> Stream.flat_map(fn %Message.Assistant{message: message} ->
      Enum.filter(message.content, &match?(%Content.ToolUse{}, &1))
    end)
  end

  @doc """
  Filters a message stream by message type.

  ## Examples

      # Only assistant messages
      stream |> ClaudeCode.Stream.filter_type(:assistant)

      # Only result messages
      stream |> ClaudeCode.Stream.filter_type(:result)
  """
  @spec filter_type(Enumerable.t(), atom()) :: Enumerable.t()
  def filter_type(stream, type) do
    Stream.filter(stream, &message_type_matches?(&1, type))
  end

  @doc """
  Takes messages until a result is received.

  This is useful when you want to process messages but stop as soon as
  the final result arrives.

  ## Examples

      messages = session
      |> ClaudeCode.query("Quick task")
      |> ClaudeCode.Stream.until_result()
      |> Enum.to_list()
  """
  @spec until_result(Enumerable.t()) :: Enumerable.t()
  def until_result(stream) do
    Stream.transform(stream, false, fn
      _message, true -> {:halt, true}
      %Message.Result{} = result, false -> {[result], true}
      message, false -> {[message], false}
    end)
  end

  @doc """
  Buffers text content until complete assistant messages are formed.

  This is useful when you want complete sentences or paragraphs rather
  than individual text fragments.

  ## Examples

      session
      |> ClaudeCode.query("Explain something")
      |> ClaudeCode.Stream.buffered_text()
      |> Enum.each(&IO.puts/1)
  """
  @spec buffered_text(Enumerable.t()) :: Enumerable.t()
  def buffered_text(stream) do
    Stream.transform(stream, "", fn
      %Message.Assistant{} = msg, buffer ->
        text = extract_text(msg)
        full_text = buffer <> text

        if String.ends_with?(text, [". ", ".\n", "! ", "!\n", "? ", "?\n"]) do
          {[full_text], ""}
        else
          {[], full_text}
        end

      %Message.Result{}, buffer ->
        if buffer == "", do: {[], ""}, else: {[buffer], ""}

      _other, buffer ->
        {[], buffer}
    end)
  end

  # Private functions

  # Remove init_stream as it's no longer needed

  defp next_message(%{done: true} = state) do
    {:halt, state}
  end

  defp next_message(%{initialized: false} = state) do
    # Initialize the stream on first message request
    case GenServer.call(state.session, {:query_async, state.prompt, state.opts}) do
      {:ok, request_ref} ->
        new_state = %{state | initialized: true, request_ref: request_ref}
        next_message(new_state)

      {:error, reason} ->
        throw({:stream_init_error, reason})
    end
  end

  defp next_message(state) do
    receive do
      {:claude_stream_started, ref} when ref == state.request_ref ->
        # CLI has started, continue waiting for messages
        next_message(state)

      {:claude_message, ref, message} when ref == state.request_ref ->
        if should_emit?(message, state.filter) do
          case message do
            %Message.Result{} ->
              {[message], %{state | done: true}}

            _ ->
              {[message], state}
          end
        else
          next_message(state)
        end

      {:claude_stream_end, ref} when ref == state.request_ref ->
        {:halt, %{state | done: true}}

      {:claude_stream_error, ref, error} when ref == state.request_ref ->
        throw({:stream_error, error})
    after
      state.timeout ->
        throw({:stream_timeout, state.request_ref})
    end
  end

  defp cleanup_stream(state) do
    # Notify session that we're done with this stream
    if state.session && state.request_ref && Process.alive?(state.session) do
      GenServer.cast(state.session, {:stream_cleanup, state.request_ref})
    end
  end

  defp should_emit?(_message, :all), do: true

  defp should_emit?(message, filter) do
    message_type_matches?(message, filter)
  end

  defp message_type_matches?(%Message.Assistant{}, :assistant), do: true
  defp message_type_matches?(%Message.Result{}, :result), do: true
  defp message_type_matches?(%Message.System{}, :system), do: true
  defp message_type_matches?(%Message.User{}, :user), do: true
  defp message_type_matches?(%StreamEvent{}, :stream_event), do: true

  defp message_type_matches?(%Message.Assistant{message: message}, :tool_use) do
    Enum.any?(message.content, &match?(%Content.ToolUse{}, &1))
  end

  # Match text delta stream events when filtering for :text_delta
  defp message_type_matches?(%StreamEvent{} = event, :text_delta) do
    StreamEvent.text_delta?(event)
  end

  defp message_type_matches?(_, _), do: false

  defp extract_text(%Message.Assistant{message: message}) do
    message.content
    |> Enum.filter(&match?(%Content.Text{}, &1))
    |> Enum.map_join("", & &1.text)
  end
end
