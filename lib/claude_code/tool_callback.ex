defmodule ClaudeCode.ToolCallback do
  @moduledoc """
  Handles post-execution tool callbacks for logging and auditing.

  This module correlates tool use requests (from Assistant messages) with their
  results (from User messages) and invokes callbacks asynchronously when results
  are received.

  ## Usage

  Configure a callback when starting a session:

      callback = fn event ->
        Logger.info("Tool \#{event.name} executed: \#{inspect(event.result)}")
      end

      {:ok, session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        tool_callback: callback
      )

  ## Event Structure

  The callback receives a map with the following keys:

  - `:name` - Tool name (e.g., "Read", "Write", "Bash")
  - `:input` - Tool input parameters (map)
  - `:result` - Tool execution result (string)
  - `:is_error` - Whether the tool execution failed (boolean)
  - `:tool_use_id` - Unique identifier for correlation (string)
  - `:timestamp` - When the result was received (DateTime)
  """

  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.UserMessage

  @type tool_event :: %{
          name: String.t(),
          input: map(),
          result: String.t(),
          is_error: boolean(),
          tool_use_id: String.t(),
          timestamp: DateTime.t()
        }

  @type pending_tools :: %{String.t() => %{name: String.t(), input: map(), started_at: DateTime.t()}}

  @doc """
  Processes a message and invokes callback when tool results are detected.

  For Assistant messages with ToolUse blocks, stores tool info in pending_tools map.
  For User messages with ToolResult blocks, correlates with pending tools and invokes callback.

  Returns `{updated_pending_tools, events}` where events is a list of tool events
  that were processed (for testing/debugging purposes).
  """
  @spec process_message(
          message :: struct(),
          pending_tools :: pending_tools(),
          callback :: (tool_event() -> any()) | nil
        ) :: {pending_tools(), [tool_event()]}
  def process_message(message, pending_tools, callback)

  # When we see an Assistant message with ToolUse, store it for later correlation
  def process_message(%AssistantMessage{message: %{content: content}}, pending_tools, _callback) when is_list(content) do
    new_pending =
      content
      |> Enum.filter(&match?(%ToolUseBlock{}, &1))
      |> Enum.reduce(pending_tools, fn tool_use, acc ->
        Map.put(acc, tool_use.id, %{
          name: tool_use.name,
          input: tool_use.input,
          started_at: DateTime.utc_now()
        })
      end)

    {new_pending, []}
  end

  # When we see a User message with ToolResult, correlate and invoke callback
  def process_message(%UserMessage{message: %{content: content}}, pending_tools, callback)
      when is_list(content) and is_function(callback, 1) do
    {remaining_pending, events} =
      content
      |> Enum.filter(&match?(%ToolResultBlock{}, &1))
      |> Enum.reduce({pending_tools, []}, fn tool_result, {pending, events} ->
        case Map.pop(pending, tool_result.tool_use_id) do
          {nil, pending} ->
            # No matching tool use found, skip
            {pending, events}

          {tool_use_info, remaining} ->
            event = %{
              name: tool_use_info.name,
              input: tool_use_info.input,
              result: tool_result.content,
              is_error: tool_result.is_error,
              tool_use_id: tool_result.tool_use_id,
              timestamp: DateTime.utc_now()
            }

            {remaining, [event | events]}
        end
      end)

    # Invoke callbacks asynchronously to avoid blocking message processing
    Enum.each(events, fn event ->
      Task.start(fn -> callback.(event) end)
    end)

    {remaining_pending, Enum.reverse(events)}
  end

  # User message with ToolResult but no callback configured
  def process_message(%UserMessage{message: %{content: content}}, pending_tools, nil) when is_list(content) do
    # Still remove from pending to prevent memory leak
    remaining_pending =
      content
      |> Enum.filter(&match?(%ToolResultBlock{}, &1))
      |> Enum.reduce(pending_tools, fn tool_result, pending ->
        Map.delete(pending, tool_result.tool_use_id)
      end)

    {remaining_pending, []}
  end

  # Any other message type - pass through unchanged
  def process_message(_message, pending_tools, _callback) do
    {pending_tools, []}
  end
end
