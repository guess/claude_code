defmodule ClaudeCode.Stream do
  @moduledoc """
  Stream utilities for handling Claude Code responses.

  This module provides functions to create and manipulate streams of messages
  from Claude Code sessions. It enables real-time processing of Claude's
  responses without waiting for the complete result.

  ## Example

      session
      |> ClaudeCode.stream("Write a story")
      |> ClaudeCode.Stream.text_content()
      |> Stream.each(&IO.write/1)
      |> Stream.run()
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Message
  alias ClaudeCode.Message.PartialAssistantMessage

  @doc """
  Creates a stream of messages from a Claude Code query.

  This is the primary function for creating message streams. It returns a
  Stream that emits messages as they arrive from the CLI.

  ## Options

    * `:stream_timeout` - Maximum time to wait for each message (default: 60_000ms)
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
          timeout: Keyword.get(opts, :stream_timeout, Keyword.get(opts, :timeout, 60_000)),
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
      |> ClaudeCode.stream("Tell me about Elixir")
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()
  """
  @spec text_content(Enumerable.t()) :: Enumerable.t()
  def text_content(stream) do
    stream
    |> Stream.filter(&match?(%Message.AssistantMessage{}, &1))
    |> Stream.flat_map(fn %Message.AssistantMessage{message: message} ->
      message.content
      |> Enum.filter(&match?(%Content.TextBlock{}, &1))
      |> Enum.map(& &1.text)
    end)
  end

  @doc """
  Extracts thinking content from a message stream.

  Filters the stream to only emit thinking content from assistant messages,
  making it easy to collect Claude's extended reasoning.

  ## Examples

      thinking = session
      |> ClaudeCode.stream("Complex problem")
      |> ClaudeCode.Stream.thinking_content()
      |> Enum.join()
  """
  @spec thinking_content(Enumerable.t()) :: Enumerable.t()
  def thinking_content(stream) do
    stream
    |> Stream.filter(&match?(%Message.AssistantMessage{}, &1))
    |> Stream.flat_map(fn %Message.AssistantMessage{message: message} ->
      message.content
      |> Enum.filter(&match?(%Content.ThinkingBlock{}, &1))
      |> Enum.map(& &1.thinking)
    end)
  end

  @doc """
  Extracts text deltas from a partial message stream.

  This enables character-by-character streaming from Claude's responses.
  Use with `include_partial_messages: true` option.

  ## Examples

      # Real-time character streaming for LiveView
      ClaudeCode.stream(session, "Tell a story", include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(fn chunk ->
        Phoenix.PubSub.broadcast(MyApp.PubSub, "chat:123", {:text_chunk, chunk})
      end)

      # Simple console output
      session
      |> ClaudeCode.stream("Hello", include_partial_messages: true)
      |> ClaudeCode.Stream.text_deltas()
      |> Enum.each(&IO.write/1)
  """
  @spec text_deltas(Enumerable.t()) :: Enumerable.t()
  def text_deltas(stream) do
    stream
    |> Stream.filter(&PartialAssistantMessage.text_delta?/1)
    |> Stream.map(&PartialAssistantMessage.get_text/1)
  end

  @doc """
  Extracts thinking deltas from a partial message stream.

  This enables streaming of Claude's extended reasoning as it arrives.
  Use with `include_partial_messages: true` option.

  ## Examples

      # Stream thinking content in real-time
      session
      |> ClaudeCode.stream("Complex problem", include_partial_messages: true)
      |> ClaudeCode.Stream.thinking_deltas()
      |> Enum.each(&IO.write/1)
  """
  @spec thinking_deltas(Enumerable.t()) :: Enumerable.t()
  def thinking_deltas(stream) do
    stream
    |> Stream.filter(&PartialAssistantMessage.thinking_delta?/1)
    |> Stream.map(&PartialAssistantMessage.get_thinking/1)
  end

  @doc """
  Extracts all content deltas from a partial message stream.

  Returns a stream of delta maps, useful for tracking both text
  and tool use input as it arrives. Each element contains:
  - `type`: `:text_delta`, `:input_json_delta`, or `:thinking_delta`
  - `index`: The content block index
  - Content-specific fields (`text`, `partial_json`, or `thinking`)

  ## Examples

      ClaudeCode.stream(session, "Create a file", include_partial_messages: true)
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
    |> Stream.filter(&match?(%PartialAssistantMessage{event: %{type: :content_block_delta}}, &1))
    |> Stream.map(fn %PartialAssistantMessage{event: %{delta: delta, index: index}} ->
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
  @spec filter_event_type(Enumerable.t(), PartialAssistantMessage.event_type()) :: Enumerable.t()
  def filter_event_type(stream, event_type) do
    Stream.filter(stream, fn
      %PartialAssistantMessage{event: %{type: ^event_type}} -> true
      _ -> false
    end)
  end

  @doc """
  Extracts tool use blocks from a message stream.

  Filters the stream to only emit tool use content blocks, making it easy
  to react to tool usage in real-time.

  ## Examples

      session
      |> ClaudeCode.stream("Create some files")
      |> ClaudeCode.Stream.tool_uses()
      |> Enum.each(&handle_tool_use/1)
  """
  @spec tool_uses(Enumerable.t()) :: Enumerable.t()
  def tool_uses(stream) do
    stream
    |> Stream.filter(&match?(%Message.AssistantMessage{}, &1))
    |> Stream.flat_map(fn %Message.AssistantMessage{message: message} ->
      Enum.filter(message.content, &match?(%Content.ToolUseBlock{}, &1))
    end)
  end

  @doc """
  Extracts tool results for a specific tool name from a message stream.

  Since tool results reference tool uses by ID (not name), this function
  tracks tool use blocks and matches their IDs with subsequent tool results.

  ## Examples

      # Get all Read tool results
      session
      |> ClaudeCode.stream("Read some files")
      |> ClaudeCode.Stream.tool_results_by_name("Read")
      |> Enum.each(&IO.inspect/1)

      # Get Bash command outputs
      session
      |> ClaudeCode.stream("Run some commands")
      |> ClaudeCode.Stream.tool_results_by_name("Bash")
      |> Enum.map(& &1.content)
  """
  @spec tool_results_by_name(Enumerable.t(), String.t()) :: Enumerable.t()
  def tool_results_by_name(stream, tool_name) do
    Stream.transform(stream, %{}, fn message, tool_use_ids ->
      case message do
        %Message.AssistantMessage{message: %{content: content}} ->
          # Track tool use IDs for the target tool
          new_ids =
            content
            |> Enum.filter(&match?(%Content.ToolUseBlock{name: ^tool_name}, &1))
            |> Map.new(&{&1.id, true})

          {[], Map.merge(tool_use_ids, new_ids)}

        %Message.UserMessage{message: %{content: content}} ->
          # Emit matching tool results
          results =
            Enum.filter(content, fn
              %Content.ToolResultBlock{tool_use_id: id} -> Map.has_key?(tool_use_ids, id)
              _ -> false
            end)

          {results, tool_use_ids}

        _ ->
          {[], tool_use_ids}
      end
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
  Returns only the final result text, consuming the stream.

  This is the most common use case - when you just want Claude's answer
  without processing intermediate messages.

  ## Examples

      # Simple query
      result = session
      |> ClaudeCode.stream("What is 2 + 2?")
      |> ClaudeCode.Stream.final_text()
      # => "2 + 2 equals 4."

      # With error handling
      case ClaudeCode.Stream.final_text(stream) do
        nil -> IO.puts("No result received")
        text -> IO.puts(text)
      end
  """
  @spec final_text(Enumerable.t()) :: String.t() | nil
  def final_text(stream) do
    Enum.find_value(stream, fn
      %Message.ResultMessage{result: result} -> result
      _ -> nil
    end)
  end

  @doc """
  Returns the final `ResultMessage`, consuming the stream.

  Use this when you need the full result struct with `stop_reason`, `usage`,
  `session_id`, and other metadata — not just the text.

  ## Examples

      result = session
      |> ClaudeCode.stream("Write a poem about the ocean")
      |> ClaudeCode.Stream.final_result()

      IO.puts("Stop reason: \#{result.stop_reason}")
      IO.puts("Cost: $\#{result.total_cost_usd}")
  """
  @spec final_result(Enumerable.t()) :: Message.ResultMessage.t() | nil
  def final_result(stream) do
    Enum.find(stream, &match?(%Message.ResultMessage{}, &1))
  end

  @doc """
  Consumes the stream and returns a structured summary of the conversation.

  Returns a map containing:
  - `text` - All text content concatenated
  - `tool_calls` - List of `{tool_use, tool_result}` tuples pairing each tool
    invocation with its result. If a tool use has no matching result, the
    result will be `nil`.
  - `thinking` - All thinking content concatenated
  - `result` - The final result text
  - `is_error` - Whether the result was an error
  - `session_id` - The session ID (useful for resuming conversations)
  - `usage` - Token usage map (input_tokens, output_tokens, cache tokens, etc.)
  - `total_cost_usd` - Total cost of the query in USD
  - `stop_reason` - Why the conversation ended (`:end_turn`, `:max_tokens`, etc.)
  - `num_turns` - Number of turns in the conversation

  ## Examples

      summary = session
      |> ClaudeCode.stream("Create a hello.txt file")
      |> ClaudeCode.Stream.collect()

      IO.puts("Claude said: \#{summary.text}")
      IO.puts("Tool calls: \#{length(summary.tool_calls)}")
      IO.puts("Final result: \#{summary.result}")
      IO.puts("Session: \#{summary.session_id}")
      IO.puts("Cost: $\#{summary.total_cost_usd}")
      IO.puts("Turns: \#{summary.num_turns}")

      # Process each tool call with its result
      Enum.each(summary.tool_calls, fn {tool_use, tool_result} ->
        IO.puts("Tool: \#{tool_use.name}")
        if tool_result, do: IO.puts("Result: \#{tool_result.content}")
      end)
  """
  @spec collect(Enumerable.t()) :: %{
          text: String.t(),
          tool_calls: [{Content.ToolUseBlock.t(), Content.ToolResultBlock.t() | nil}],
          thinking: String.t(),
          result: String.t() | nil,
          is_error: boolean(),
          session_id: String.t() | nil,
          usage: map() | nil,
          total_cost_usd: float() | nil,
          stop_reason: atom() | nil,
          num_turns: non_neg_integer() | nil
        }
  def collect(stream) do
    initial = %{
      text: [],
      # Map of tool_use_id => ToolUseBlock for pairing
      tool_use_map: %{},
      # Ordered list of tool_use_ids to preserve order
      tool_use_order: [],
      # Map of tool_use_id => ToolResultBlock
      tool_result_map: %{},
      thinking: [],
      result: nil,
      is_error: false,
      session_id: nil,
      usage: nil,
      total_cost_usd: nil,
      stop_reason: nil,
      num_turns: nil
    }

    stream
    |> Enum.reduce(initial, fn
      %Message.AssistantMessage{message: message}, acc ->
        {text, thinking, tools} = extract_content_parts(message.content)

        # Track tool uses by ID
        {tool_use_map, tool_use_order} =
          Enum.reduce(tools, {acc.tool_use_map, acc.tool_use_order}, fn tool, {map, order} ->
            {Map.put(map, tool.id, tool), order ++ [tool.id]}
          end)

        %{
          acc
          | text: acc.text ++ text,
            thinking: acc.thinking ++ thinking,
            tool_use_map: tool_use_map,
            tool_use_order: tool_use_order
        }

      %Message.UserMessage{message: message}, acc ->
        # Extract tool results and index by tool_use_id
        tool_result_map =
          message.content
          |> Enum.filter(&match?(%Content.ToolResultBlock{}, &1))
          |> Enum.reduce(acc.tool_result_map, fn result, map ->
            Map.put(map, result.tool_use_id, result)
          end)

        %{acc | tool_result_map: tool_result_map}

      %Message.ResultMessage{} = result_msg, acc ->
        %{
          acc
          | result: result_msg.result,
            is_error: result_msg.is_error,
            session_id: result_msg.session_id,
            usage: result_msg.usage,
            total_cost_usd: result_msg.total_cost_usd,
            stop_reason: result_msg.stop_reason,
            num_turns: result_msg.num_turns
        }

      _, acc ->
        acc
    end)
    |> then(fn acc ->
      # Pair tool uses with their results in order
      tool_calls =
        Enum.map(acc.tool_use_order, fn id ->
          tool_use = Map.fetch!(acc.tool_use_map, id)
          tool_result = Map.get(acc.tool_result_map, id)
          {tool_use, tool_result}
        end)

      %{
        text: Enum.join(acc.text),
        tool_calls: tool_calls,
        thinking: Enum.join(acc.thinking),
        result: acc.result,
        is_error: acc.is_error,
        session_id: acc.session_id,
        usage: acc.usage,
        total_cost_usd: acc.total_cost_usd,
        stop_reason: acc.stop_reason,
        num_turns: acc.num_turns
      }
    end)
  end

  @doc """
  Applies a side-effect function to each message without filtering.

  This is useful for logging, monitoring, or sending events while still
  allowing the stream to continue unchanged. Unlike `Stream.each/2`, this
  is designed for observation within a pipeline.

  ## Examples

      # Logging all messages
      stream
      |> ClaudeCode.Stream.tap(fn msg -> Logger.debug("Got: \#{inspect(msg)}") end)
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()

      # Progress notifications
      stream
      |> ClaudeCode.Stream.tap(&send(progress_pid, {:message, &1}))
      |> ClaudeCode.Stream.final_text()
  """
  @spec tap(Enumerable.t(), (Message.t() -> any())) :: Enumerable.t()
  def tap(stream, fun) when is_function(fun, 1) do
    Stream.each(stream, fun)
  end

  @doc """
  Invokes a callback whenever a tool is used, without filtering the stream.

  This is useful for progress indicators, logging, or triggering side effects
  when Claude uses tools. The callback receives each `ToolUseBlock`.

  ## Examples

      # Progress indicator for tool usage
      stream
      |> ClaudeCode.Stream.on_tool_use(fn tool ->
        IO.puts("Using tool: \#{tool.name}")
      end)
      |> ClaudeCode.Stream.final_text()

      # Send tool events to a LiveView process
      stream
      |> ClaudeCode.Stream.on_tool_use(fn tool ->
        send(liveview_pid, {:tool_started, tool.name, tool.input})
      end)
      |> Enum.to_list()

      # Track tool usage
      stream
      |> ClaudeCode.Stream.on_tool_use(&Agent.update(tracker, fn tools -> [&1 | tools] end))
      |> ClaudeCode.Stream.collect()
  """
  @spec on_tool_use(Enumerable.t(), (Content.ToolUseBlock.t() -> any())) :: Enumerable.t()
  def on_tool_use(stream, callback) when is_function(callback, 1) do
    Stream.each(stream, fn
      %Message.AssistantMessage{message: message} ->
        message.content
        |> Enum.filter(&match?(%Content.ToolUseBlock{}, &1))
        |> Enum.each(callback)

      _ ->
        :ok
    end)
  end

  @doc """
  Takes messages until a result is received.

  This is useful when you want to process messages but stop as soon as
  the final result arrives.

  ## Examples

      messages = session
      |> ClaudeCode.stream("Quick task")
      |> ClaudeCode.Stream.until_result()
      |> Enum.to_list()
  """
  @spec until_result(Enumerable.t()) :: Enumerable.t()
  def until_result(stream) do
    Stream.transform(stream, false, fn
      _message, true -> {:halt, true}
      %Message.ResultMessage{} = result, false -> {[result], true}
      message, false -> {[message], false}
    end)
  end

  # Private functions

  # Remove init_stream as it's no longer needed

  defp next_message(%{done: true} = state) do
    {:halt, state}
  end

  defp next_message(%{initialized: false} = state) do
    # Initialize the stream on first message request
    case GenServer.call(state.session, {:query_stream, state.prompt, state.opts}) do
      {:ok, request_ref} ->
        new_state = %{state | initialized: true, request_ref: request_ref}
        next_message(new_state)

      {:error, reason} ->
        throw({:stream_init_error, reason})
    end
  end

  defp next_message(state) do
    # Use receive_next to get messages from the session (pull-based)
    case GenServer.call(state.session, {:receive_next, state.request_ref}, state.timeout) do
      {:message, message} ->
        if should_emit?(message, state.filter) do
          case message do
            %Message.ResultMessage{} ->
              {[message], %{state | done: true}}

            _ ->
              {[message], state}
          end
        else
          next_message(state)
        end

      :done ->
        {:halt, %{state | done: true}}

      {:error, reason} ->
        throw({:stream_error, reason})
    end
  catch
    :exit, {:timeout, _} ->
      throw({:stream_timeout, state.request_ref})
  end

  defp cleanup_stream(state) do
    # Notify session that we're done with this stream
    # Handle both pid and named process references
    if state.session && state.request_ref && process_alive?(state.session) do
      GenServer.cast(state.session, {:stream_cleanup, state.request_ref})
    end
  end

  defp process_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp process_alive?(name) when is_atom(name), do: GenServer.whereis(name) != nil
  defp process_alive?({:via, _, _} = name), do: GenServer.whereis(name) != nil
  defp process_alive?({:global, _} = name), do: GenServer.whereis(name) != nil
  defp process_alive?({name, _node} = ref) when is_atom(name), do: GenServer.whereis(ref) != nil
  defp process_alive?(_), do: false

  defp should_emit?(_message, :all), do: true

  defp should_emit?(message, filter) do
    message_type_matches?(message, filter)
  end

  defp message_type_matches?(%Message.AssistantMessage{}, :assistant), do: true
  defp message_type_matches?(%Message.ResultMessage{}, :result), do: true
  defp message_type_matches?(%Message.SystemMessage{}, :system), do: true
  defp message_type_matches?(%Message.UserMessage{}, :user), do: true
  defp message_type_matches?(%PartialAssistantMessage{}, :stream_event), do: true
  defp message_type_matches?(%Message.RateLimitEvent{}, :rate_limit_event), do: true
  defp message_type_matches?(%Message.ToolProgressMessage{}, :tool_progress), do: true
  defp message_type_matches?(%Message.ToolUseSummaryMessage{}, :tool_use_summary), do: true
  defp message_type_matches?(%Message.AuthStatusMessage{}, :auth_status), do: true
  defp message_type_matches?(%Message.PromptSuggestionMessage{}, :prompt_suggestion), do: true

  defp message_type_matches?(%Message.AssistantMessage{message: message}, :tool_use) do
    Enum.any?(message.content, &match?(%Content.ToolUseBlock{}, &1))
  end

  # Match text delta partial messages when filtering for :text_delta
  defp message_type_matches?(%PartialAssistantMessage{} = event, :text_delta) do
    PartialAssistantMessage.text_delta?(event)
  end

  defp message_type_matches?(_, _), do: false

  defp extract_content_parts(content) do
    Enum.reduce(content, {[], [], []}, fn
      %Content.TextBlock{text: text}, {texts, thinking, tools} ->
        {texts ++ [text], thinking, tools}

      %Content.ThinkingBlock{thinking: thought}, {texts, thinking, tools} ->
        {texts, thinking ++ [thought], tools}

      %Content.ToolUseBlock{} = tool, {texts, thinking, tools} ->
        {texts, thinking, tools ++ [tool]}

      _, acc ->
        acc
    end)
  end
end
