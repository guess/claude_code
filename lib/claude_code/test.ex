defmodule ClaudeCode.Test do
  @moduledoc """
  Req.Test-style test helpers for ClaudeCode.

  This module provides a simple way to mock Claude responses in your tests,
  following the same patterns as Req.Test.

  ## Setup

  1. Configure the adapter in your test environment:

      ```elixir
      # config/test.exs
      config :claude_code, adapter: {ClaudeCode.Test, ClaudeCode.Session}
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
        ClaudeCode.Test.stub(ClaudeCode.Session, fn _query, _opts ->
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
  - `tool_use/1` - Creates a tool invocation message
  - `tool_result/1` - Creates a tool result message
  - `thinking/1` - Creates a thinking block message
  - `result/1` - Creates the final result message
  - `system/1` - Creates a system initialization message

  ## Async Tests

  This module uses `NimbleOwnership` for process-based isolation, allowing
  concurrent test execution. Stubs registered in a test process are only
  visible to that process and its allowees.

  To allow a spawned process to access stubs:

      ClaudeCode.Test.allow(ClaudeCode.Session, self(), pid_of_spawned_process)
  """

  alias ClaudeCode.Content
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.UserMessage

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

      ClaudeCode.Test.stub(ClaudeCode.Session, fn query, opts ->
        [
          ClaudeCode.Test.text("Response to: \#{query}"),
          ClaudeCode.Test.result()
        ]
      end)

  ## Static stub

  A list of messages that will be returned for any query:

      ClaudeCode.Test.stub(ClaudeCode.Session, [
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
        ClaudeCode.Test.stub(ClaudeCode.Session, fn _, _ -> [...] end)

        task = Task.async(fn ->
          # This task can now access the stub
          {:ok, session} = ClaudeCode.start_link([])
          ClaudeCode.stream(session, "hi") |> Enum.to_list()
        end)

        # Allow the task to access our stubs
        ClaudeCode.Test.allow(ClaudeCode.Session, self(), task.pid)

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
    %AssistantMessage{
      type: :assistant,
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      uuid: nil,
      parent_tool_use_id: nil,
      message: %{
        id: Keyword.get(opts, :message_id, generate_message_id()),
        type: :message,
        role: :assistant,
        model: Keyword.get(opts, :model, "claude-sonnet-4-20250514"),
        content: [%Content.TextBlock{type: :text, text: text}],
        stop_reason: Keyword.get(opts, :stop_reason),
        stop_sequence: nil,
        usage: default_usage()
      }
    }
  end

  @doc """
  Creates an assistant message with a tool use block.

  ## Options (required)

  - `:name` - Tool name (e.g., "Read", "Bash", "Edit")
  - `:input` - Tool input map

  ## Options (optional)

  - `:id` - Tool use ID (default: auto-generated)
  - `:text` - Optional text to include before the tool use
  - `:session_id` - Session ID (default: auto-generated)

  ## Examples

      ClaudeCode.Test.tool_use(name: "Read", input: %{path: "/tmp/file.txt"})
      ClaudeCode.Test.tool_use(name: "Bash", input: %{command: "ls -la"}, text: "Let me check...")
  """
  @spec tool_use(keyword()) :: AssistantMessage.t()
  def tool_use(opts) do
    name = Keyword.fetch!(opts, :name)
    input = Keyword.fetch!(opts, :input)
    id = Keyword.get(opts, :id, generate_tool_id())
    text_content = Keyword.get(opts, :text)

    tool_use_block = %Content.ToolUseBlock{
      type: :tool_use,
      id: id,
      name: name,
      input: input
    }

    content =
      if text_content do
        [%Content.TextBlock{type: :text, text: text_content}, tool_use_block]
      else
        [tool_use_block]
      end

    %AssistantMessage{
      type: :assistant,
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      uuid: nil,
      parent_tool_use_id: nil,
      message: %{
        id: Keyword.get(opts, :message_id, generate_message_id()),
        type: :message,
        role: :assistant,
        model: Keyword.get(opts, :model, "claude-sonnet-4-20250514"),
        content: content,
        stop_reason: :tool_use,
        stop_sequence: nil,
        usage: default_usage()
      }
    }
  end

  @doc """
  Creates a user message with a tool result block.

  ## Options

  - `:content` - Tool result content string (default: "")
  - `:tool_use_id` - ID of the tool use this is responding to (default: auto-generated)
  - `:is_error` - Whether the tool execution failed (default: false)
  - `:session_id` - Session ID (default: auto-generated)

  ## Examples

      ClaudeCode.Test.tool_result(content: "file contents here")
      ClaudeCode.Test.tool_result(content: "Permission denied", is_error: true)
  """
  @spec tool_result(keyword()) :: UserMessage.t()
  def tool_result(opts \\ []) do
    content = Keyword.get(opts, :content, "")
    # Default to nil so auto-linking can work
    tool_use_id = Keyword.get(opts, :tool_use_id)
    is_error = Keyword.get(opts, :is_error, false)

    %UserMessage{
      type: :user,
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      uuid: nil,
      parent_tool_use_id: nil,
      message: %{
        role: :user,
        content: [
          %Content.ToolResultBlock{
            type: :tool_result,
            tool_use_id: tool_use_id,
            content: content,
            is_error: is_error
          }
        ]
      }
    }
  end

  @doc """
  Creates an assistant message with a thinking block.

  ## Options

  - `:thinking` - The thinking content (required)
  - `:signature` - Thinking signature (default: auto-generated)
  - `:text` - Optional text to include after thinking
  - `:session_id` - Session ID (default: auto-generated)

  ## Examples

      ClaudeCode.Test.thinking(thinking: "Let me analyze this step by step...")
      ClaudeCode.Test.thinking(thinking: "First...", text: "Here's my answer")
  """
  @spec thinking(keyword()) :: AssistantMessage.t()
  def thinking(opts) do
    thinking_text = Keyword.fetch!(opts, :thinking)
    signature = Keyword.get(opts, :signature, generate_signature())
    text_content = Keyword.get(opts, :text)

    thinking_block = %Content.ThinkingBlock{
      type: :thinking,
      thinking: thinking_text,
      signature: signature
    }

    content =
      if text_content do
        [thinking_block, %Content.TextBlock{type: :text, text: text_content}]
      else
        [thinking_block]
      end

    %AssistantMessage{
      type: :assistant,
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      uuid: nil,
      parent_tool_use_id: nil,
      message: %{
        id: Keyword.get(opts, :message_id, generate_message_id()),
        type: :message,
        role: :assistant,
        model: Keyword.get(opts, :model, "claude-sonnet-4-20250514"),
        content: content,
        stop_reason: nil,
        stop_sequence: nil,
        usage: default_usage()
      }
    }
  end

  @doc """
  Creates a final result message.

  ## Options

  - `:result` - The result text (default: "Done")
  - `:is_error` - Whether this is an error result (default: false)
  - `:subtype` - Result subtype (default: :success or :error_during_execution)
  - `:session_id` - Session ID (default: auto-generated)
  - `:duration_ms` - Duration in milliseconds (default: 100)
  - `:num_turns` - Number of turns (default: 1)

  ## Examples

      ClaudeCode.Test.result()
      ClaudeCode.Test.result(result: "Task completed successfully")
      ClaudeCode.Test.result(is_error: true, result: "Rate limit exceeded")
  """
  @spec result(keyword()) :: ResultMessage.t()
  def result(opts \\ []) do
    is_error = Keyword.get(opts, :is_error, false)
    default_subtype = if is_error, do: :error_during_execution, else: :success

    %ResultMessage{
      type: :result,
      subtype: Keyword.get(opts, :subtype, default_subtype),
      is_error: is_error,
      duration_ms: Keyword.get(opts, :duration_ms, 100),
      duration_api_ms: Keyword.get(opts, :duration_api_ms, 80),
      num_turns: Keyword.get(opts, :num_turns, 1),
      result: Keyword.get(opts, :result, "Done"),
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      total_cost_usd: Keyword.get(opts, :total_cost_usd, 0.001),
      usage: Keyword.get(opts, :usage, %{}),
      uuid: nil,
      model_usage: nil,
      permission_denials: nil,
      structured_output: nil,
      errors: nil
    }
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
    %SystemMessage{
      type: :system,
      subtype: :init,
      uuid: generate_uuid(),
      model: Keyword.get(opts, :model, "claude-sonnet-4-20250514"),
      session_id: Keyword.get(opts, :session_id, generate_session_id()),
      cwd: Keyword.get(opts, :cwd, "/test"),
      tools: Keyword.get(opts, :tools, []),
      mcp_servers: Keyword.get(opts, :mcp_servers, []),
      permission_mode: Keyword.get(opts, :permission_mode, "auto"),
      api_key_source: Keyword.get(opts, :api_key_source, "ANTHROPIC_API_KEY"),
      slash_commands: Keyword.get(opts, :slash_commands, []),
      output_style: Keyword.get(opts, :output_style, "default")
    }
  end

  # ============================================================================
  # Stream Building
  # ============================================================================

  defp build_stream(messages, opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

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
            %Content.TextBlock{text: t} -> t
            _ -> nil
          end)

        messages ++ [result(result: last_text || "Done", session_id: session_id)]

      _ ->
        messages ++ [result(session_id: session_id)]
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
                %Content.ToolUseBlock{id: id} -> id
                _ -> nil
              end)

            {msg, tool_id || last_tool_id}

          %UserMessage{message: %{content: [%Content.ToolResultBlock{tool_use_id: id} = block | rest]}}
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
  # ID Generators
  # ============================================================================

  defp generate_session_id, do: "test-#{:rand.uniform(999_999)}"
  defp generate_message_id, do: "msg_test_#{:rand.uniform(999_999)}"
  defp generate_tool_id, do: "toolu_test_#{:rand.uniform(999_999)}"
  defp generate_signature, do: "sig_test_#{:rand.uniform(999_999)}"
  defp generate_uuid, do: "#{:rand.uniform(999_999)}-#{:rand.uniform(999_999)}"

  defp default_usage do
    %{
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: nil,
      cache_read_input_tokens: nil,
      server_tool_use: nil
    }
  end
end
