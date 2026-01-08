defmodule ClaudeCode.Test do
  @moduledoc """
  Req.Test-style test helpers for ClaudeCode.

  This module provides a simple way to mock Claude responses in your tests,
  following the same patterns as Req.Test.

  ## Setup

  1. Configure the adapter in your test environment:

      ```elixir
      # config/test.exs
      config :claude_code, adapter: {ClaudeCode.Test, ClaudeCode}
      ```

  2. In your test helper, start the ownership server:

      ```elixir
      # test/test_helper.exs
      ExUnit.start()
      Supervisor.start_link([ClaudeCode.Test], strategy: :one_for_one)
      ```

  3. Register stubs in your tests:

      ```elixir
      test "returns greeting" do
        ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
          [
            ClaudeCode.Test.text("Hello! How can I help?"),
            ClaudeCode.Test.result()
          ]
        end)

        {:ok, session} = ClaudeCode.start_link([])
        result = session |> ClaudeCode.stream("Hi") |> ClaudeCode.Stream.final_text()
        assert result == "Hello! How can I help?"
      end
      ```

  ## Message Helpers

  - `text/2` - Creates an assistant message with text content
  - `tool_use/3` - Creates a tool invocation message
  - `tool_result/2` - Creates a tool result message
  - `thinking/2` - Creates a thinking block message
  - `result/2` - Creates the final result message
  - `system/1` - Creates a system initialization message

  ## Async Tests

  This module uses `NimbleOwnership` for process-based isolation, allowing
  concurrent test execution. Stubs registered in a test process are only
  visible to that process and its allowees.

  To allow a spawned process to access stubs:

      ClaudeCode.Test.allow(ClaudeCode, self(), pid_of_spawned_process)

  ## Using Different Names

  The name in `{ClaudeCode.Test, name}` can be any term. This is useful when
  you need different stub behaviors in the same test, or when building wrapper
  modules around ClaudeCode:

      # Testing multiple "agents" with different behaviors
      ClaudeCode.Test.stub(MyApp.CodingAgent, fn _query, _opts ->
        [ClaudeCode.Test.text("Here's the code...")]
      end)

      ClaudeCode.Test.stub(MyApp.ResearchAgent, fn _query, _opts ->
        [ClaudeCode.Test.text("Based on my research...")]
      end)

      {:ok, coder} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, MyApp.CodingAgent})
      {:ok, researcher} = ClaudeCode.start_link(adapter: {ClaudeCode.Test, MyApp.ResearchAgent})
  """

  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.UserMessage
  alias ClaudeCode.Test.Factory

  @ownership __MODULE__.Ownership

  # ============================================================================
  # Supervisor Child Spec
  # ============================================================================

  @doc false
  def child_spec(_opts) do
    %{
      id: @ownership,
      start: {NimbleOwnership, :start_link, [[name: @ownership]]}
    }
  end

  # ============================================================================
  # Stub Registration
  # ============================================================================

  @doc """
  Registers a stub for the given name.

  The stub can be either a function or a list of messages:

  ## Function stub

  Receives the query and options, returns a list of messages:

      ClaudeCode.Test.stub(ClaudeCode, fn query, opts ->
        [
          ClaudeCode.Test.text("Response to: \#{query}"),
          ClaudeCode.Test.result()
        ]
      end)

  ## Static stub

  A list of messages that will be returned for any query:

      ClaudeCode.Test.stub(ClaudeCode, [
        ClaudeCode.Test.text("Static response"),
        ClaudeCode.Test.result()
      ])
  """
  @spec stub(name :: term(), fun_or_messages :: (String.t(), keyword() -> [term()]) | [term()]) ::
          :ok
  def stub(name, fun_or_messages) do
    case NimbleOwnership.fetch_owner(@ownership, default_callers(), name) do
      {:ok, _owner} ->
        # Already owned, update the stub
        NimbleOwnership.get_and_update(@ownership, self(), name, fn _ ->
          {:ok, fun_or_messages}
        end)

      :error ->
        # Not owned, claim ownership
        NimbleOwnership.get_and_update(@ownership, self(), name, fn _ ->
          {:ok, fun_or_messages}
        end)
    end

    :ok
  end

  @doc """
  Allows `pid_to_allow` to access stubs owned by `owner_pid`.

  This is useful when you spawn processes that need to access the same stubs
  as the test process.

  ## Example

      test "spawned process can use stub" do
        ClaudeCode.Test.stub(ClaudeCode, fn _, _ -> [...] end)

        task = Task.async(fn ->
          # This task can now access the stub
          {:ok, session} = ClaudeCode.start_link([])
          ClaudeCode.stream(session, "hi") |> Enum.to_list()
        end)

        # Allow the task to access our stubs
        ClaudeCode.Test.allow(ClaudeCode, self(), task.pid)

        Task.await(task)
      end
  """
  @spec allow(name :: term(), owner_pid :: pid(), pid_to_allow :: pid()) :: :ok | {:error, term()}
  def allow(name, owner_pid, pid_to_allow) do
    NimbleOwnership.allow(@ownership, owner_pid, pid_to_allow, name)
  end

  @doc """
  Sets the mode to shared global.

  In shared mode, all processes can access stubs without explicit allowances.
  This is useful for integration tests or when process ownership is complex.

  ## Example

      setup do
        ClaudeCode.Test.set_mode_to_shared()
        :ok
      end
  """
  @spec set_mode_to_shared() :: :ok
  def set_mode_to_shared do
    NimbleOwnership.set_mode_to_shared(@ownership, self())
  end

  # ============================================================================
  # Message Stream
  # ============================================================================

  @doc """
  Returns a list of messages from the registered stub.

  Called by `ClaudeCode.Adapter.Test` to retrieve stub messages.
  The optional `callers` argument allows passing the caller chain from
  a different process (used by the test adapter).
  """
  def stream(name, query, opts, callers \\ nil) do
    caller_chain = callers || default_callers()

    case fetch_stub(name, caller_chain) do
      {:ok, fun} when is_function(fun, 2) ->
        messages = fun.(query, opts)
        build_stream(messages, opts)

      {:ok, messages} when is_list(messages) ->
        build_stream(messages, opts)

      :error ->
        raise """
        no stub found for #{inspect(name)}.

        Make sure you have called ClaudeCode.Test.stub/2 in your test:

            ClaudeCode.Test.stub(#{inspect(name)}, fn query, opts ->
              [ClaudeCode.Test.text("response")]
            end)
        """
    end
  end

  defp fetch_stub(name, callers) do
    case NimbleOwnership.fetch_owner(@ownership, callers, name) do
      {tag, owner} when tag in [:ok, :shared_owner] ->
        # get_owned returns the entire map of owned data for this owner
        case NimbleOwnership.get_owned(@ownership, owner) do
          %{^name => stub} -> {:ok, stub}
          _ -> :error
        end

      :error ->
        :error
    end
  end

  defp default_callers do
    [self() | Process.get(:"$callers") || []]
  end

  # ============================================================================
  # Message Builders
  # ============================================================================

  @doc """
  Creates an assistant message with text content.

  ## Options

  - `:session_id` - Session ID (default: auto-generated)
  - `:stop_reason` - Stop reason atom (default: nil)
  - `:message_id` - Message ID (default: auto-generated)

  ## Examples

      ClaudeCode.Test.text("Hello world!")
      ClaudeCode.Test.text("Done", stop_reason: :end_turn)
  """
  @spec text(String.t(), keyword()) :: AssistantMessage.t()
  def text(text, opts \\ []) do
    message_opts =
      opts
      |> Keyword.take([:message_id, :model, :stop_reason])
      |> Keyword.put(:content, [Factory.text_block(text: text)])
      |> rename_key(:message_id, :id)

    assistant_opts =
      opts
      |> Keyword.take([:session_id])
      |> Keyword.put(:message, Map.new(message_opts))

    Factory.assistant_message(assistant_opts)
  end

  @doc """
  Creates an assistant message with a tool use block.

  ## Options

  - `:id` - Tool use ID (default: auto-generated)
  - `:text` - Optional text to include before the tool use
  - `:session_id` - Session ID (default: auto-generated)

  ## Examples

      ClaudeCode.Test.tool_use("Read", %{path: "/tmp/file.txt"})
      ClaudeCode.Test.tool_use("Bash", %{command: "ls -la"}, text: "Let me check...")
  """
  @spec tool_use(String.t(), map(), keyword()) :: AssistantMessage.t()
  def tool_use(name, input, opts \\ []) do
    text_content = Keyword.get(opts, :text)

    tool_use_block = Factory.tool_use_content(name, input, Keyword.get(opts, :id))

    content =
      if text_content do
        [Factory.text_block(text: text_content), tool_use_block]
      else
        [tool_use_block]
      end

    message_opts =
      opts
      |> Keyword.take([:message_id, :model])
      |> Keyword.merge(content: content, stop_reason: :tool_use)
      |> rename_key(:message_id, :id)

    assistant_opts =
      opts
      |> Keyword.take([:session_id])
      |> Keyword.put(:message, Map.new(message_opts))

    Factory.assistant_message(assistant_opts)
  end

  @doc """
  Creates a user message with a tool result block.

  The content can be a string or a map. Maps are automatically JSON-encoded.

  ## Options

  - `:tool_use_id` - ID of the tool use this is responding to (default: nil for auto-linking)
  - `:is_error` - Whether the tool execution failed (default: false)
  - `:session_id` - Session ID (default: auto-generated)

  ## Examples

      ClaudeCode.Test.tool_result("file contents here")
      ClaudeCode.Test.tool_result("Permission denied", is_error: true)
      ClaudeCode.Test.tool_result(%{status: "success", data: [1, 2, 3]})
  """
  @spec tool_result(String.t() | map(), keyword()) :: UserMessage.t()
  def tool_result(content \\ "", opts \\ []) do
    encoded_content = encode_content(content)

    # Use tool_result_block directly to preserve nil tool_use_id for auto-linking
    result_block =
      Factory.tool_result_block(
        content: encoded_content,
        tool_use_id: Keyword.get(opts, :tool_use_id),
        is_error: Keyword.get(opts, :is_error, false)
      )

    user_opts =
      opts
      |> Keyword.take([:session_id])
      |> Keyword.put(:message, %{content: [result_block]})

    Factory.user_message(user_opts)
  end

  defp encode_content(content) when is_map(content), do: Jason.encode!(content)
  defp encode_content(content) when is_binary(content), do: content

  @doc """
  Creates an assistant message with a thinking block.

  ## Options

  - `:signature` - Thinking signature (default: auto-generated)
  - `:text` - Optional text to include after thinking
  - `:session_id` - Session ID (default: auto-generated)

  ## Examples

      ClaudeCode.Test.thinking("Let me analyze this step by step...")
      ClaudeCode.Test.thinking("First...", text: "Here's my answer")
  """
  @spec thinking(String.t(), keyword()) :: AssistantMessage.t()
  def thinking(thinking_text, opts \\ []) do
    thinking_block = Factory.thinking_content(thinking_text, Keyword.get(opts, :signature))

    text_content = Keyword.get(opts, :text)

    content =
      if text_content do
        [thinking_block, Factory.text_block(text: text_content)]
      else
        [thinking_block]
      end

    message_opts =
      opts
      |> Keyword.take([:message_id, :model])
      |> Keyword.put(:content, content)
      |> rename_key(:message_id, :id)

    assistant_opts =
      opts
      |> Keyword.take([:session_id])
      |> Keyword.put(:message, Map.new(message_opts))

    Factory.assistant_message(assistant_opts)
  end

  @doc """
  Creates a final result message.

  ## Options

  - `:is_error` - Whether this is an error result (default: false)
  - `:subtype` - Result subtype (default: :success or :error_during_execution)
  - `:session_id` - Session ID (default: auto-generated)
  - `:duration_ms` - Duration in milliseconds (default: 100)
  - `:num_turns` - Number of turns (default: 1)

  ## Examples

      ClaudeCode.Test.result()
      ClaudeCode.Test.result("Task completed successfully")
      ClaudeCode.Test.result("Rate limit exceeded", is_error: true)
  """
  @spec result(String.t(), keyword()) :: ResultMessage.t()
  def result(result_text \\ "Done", opts \\ []) do
    is_error = Keyword.get(opts, :is_error, false)
    default_subtype = if is_error, do: :error_during_execution, else: :success

    opts
    |> Keyword.put_new(:subtype, default_subtype)
    |> Keyword.put(:result, result_text)
    |> Factory.result_message()
  end

  @doc """
  Creates a system initialization message.

  ## Options

  - `:session_id` - Session ID (default: auto-generated)
  - `:model` - Model name (default: "claude-sonnet-4-20250514")
  - `:tools` - List of available tools (default: [])
  - `:cwd` - Current working directory (default: "/test")

  ## Examples

      ClaudeCode.Test.system()
      ClaudeCode.Test.system(model: "claude-opus-4-20250514", tools: ["Read", "Edit"])
  """
  @spec system(keyword()) :: SystemMessage.t()
  def system(opts \\ []) do
    Factory.system_message(opts)
  end

  # ============================================================================
  # Stream Building
  # ============================================================================

  defp build_stream(messages, opts) do
    session_id = Keyword.get_lazy(opts, :session_id, &Factory.generate_session_id/0)

    messages
    |> ensure_system_message(session_id)
    |> link_tool_ids()
    |> ensure_result_message(session_id)
    |> unify_session_ids(session_id)
  end

  defp ensure_system_message(messages, session_id) do
    case messages do
      [%SystemMessage{} | _] -> messages
      _ -> [system(session_id: session_id) | messages]
    end
  end

  defp ensure_result_message(messages, session_id) do
    case List.last(messages) do
      %ResultMessage{} ->
        messages

      %AssistantMessage{message: %{content: content}} ->
        # Extract last text as result
        last_text =
          content
          |> Enum.reverse()
          |> Enum.find_value(fn
            %TextBlock{text: t} -> t
            _ -> nil
          end)

        messages ++ [result(last_text || "Done", session_id: session_id)]

      _ ->
        messages ++ [result("Done", session_id: session_id)]
    end
  end

  defp link_tool_ids(messages) do
    # Auto-link tool_use IDs to subsequent tool_result messages
    {linked, _last_tool_id} =
      Enum.map_reduce(messages, nil, fn msg, last_tool_id ->
        case msg do
          %AssistantMessage{message: %{content: content}} ->
            # Extract tool_use ID if present
            tool_id =
              Enum.find_value(content, fn
                %ToolUseBlock{id: id} -> id
                _ -> nil
              end)

            {msg, tool_id || last_tool_id}

          %UserMessage{message: %{content: [%ToolResultBlock{tool_use_id: id} = block | rest]}}
          when is_nil(id) or id == "" ->
            # Link to last tool_use ID
            if last_tool_id do
              updated_block = %{block | tool_use_id: last_tool_id}
              updated_msg = %{msg | message: %{msg.message | content: [updated_block | rest]}}
              {updated_msg, nil}
            else
              {msg, last_tool_id}
            end

          _ ->
            {msg, last_tool_id}
        end
      end)

    linked
  end

  defp unify_session_ids(messages, session_id) do
    Enum.map(messages, fn
      %{session_id: _} = msg -> %{msg | session_id: session_id}
      msg -> msg
    end)
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp rename_key(keywords, old_key, new_key) do
    case Keyword.pop(keywords, old_key) do
      {nil, keywords} -> keywords
      {value, keywords} -> Keyword.put(keywords, new_key, value)
    end
  end
end
