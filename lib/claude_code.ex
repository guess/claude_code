defmodule ClaudeCode do
  @moduledoc """
  Elixir SDK for Claude Code CLI.

  This module provides the main interface for interacting with Claude Code
  through the command-line interface. It manages sessions as GenServer processes
  that maintain persistent CLI subprocesses for efficient bidirectional communication.

  ## Quick Start

      # Start a single session (auto-connects to CLI)
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")
      {:ok, response} = ClaudeCode.query(session, "Hello, Claude!")
      IO.puts(response)

  ## Session Lifecycle

  Sessions automatically connect to the Claude CLI on startup and disconnect on stop.
  The persistent connection enables:
  - Efficient multi-turn conversations without CLI restart overhead
  - Automatic session continuity via session IDs
  - Real-time streaming of responses

  ## Supervision for Production

  For production applications, use the supervisor for fault tolerance and
  automatic restart capabilities:

      # In your application supervision tree
      children = [
        {ClaudeCode.Supervisor, [
          [name: :code_reviewer, api_key: api_key, system_prompt: "You review Elixir code"],
          [name: :test_writer, api_key: api_key, system_prompt: "You write ExUnit tests"]
        ]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      # Access supervised sessions from anywhere
      {:ok, response} = ClaudeCode.query(:code_reviewer, "Review this function")

  ## Resume Previous Conversations

      # Get session ID from a previous interaction
      {:ok, session_id} = ClaudeCode.get_session_id(session)

      # Later: resume the conversation
      {:ok, new_session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        resume: session_id
      )
      {:ok, response} = ClaudeCode.query(new_session, "Continue where we left off")

  ## Session Management Patterns

  ### Static Named Sessions (Recommended for most use cases)

  Best for long-lived assistants with specific roles:

      # In supervision tree
      {ClaudeCode.Supervisor, [
        [name: {:global, :main_assistant}, api_key: api_key],
        [name: :local_helper, api_key: api_key]
      ]}

      # Access from anywhere in your application
      ClaudeCode.query({:global, :main_assistant}, "Help me with this bug")

  ### Dynamic On-Demand Sessions

  Best for temporary or user-specific contexts:

      # Create as needed
      {:ok, session} = ClaudeCode.start_link(
        api_key: user_api_key,
        system_prompt: "Help user #\{user_id\}"
      )

      # Use and let it terminate naturally
      {:ok, result} = ClaudeCode.query(session, prompt)

  See `ClaudeCode.Supervisor` for advanced supervision patterns.
  """

  alias ClaudeCode.Session

  @type session :: pid() | atom() | {:via, module(), any()}
  @type query_response :: {:ok, String.t()} | {:error, term()}
  @type message_stream :: Enumerable.t(ClaudeCode.Message.t())

  @doc """
  Starts a new Claude Code session.

  The session automatically connects to a persistent CLI subprocess on startup.
  This enables efficient multi-turn conversations without CLI restart overhead.

  ## Options

  For complete option documentation including types, validation rules, and examples,
  see `ClaudeCode.Options.session_schema/0` and the `ClaudeCode.Options` module.

  Key options:
  - `:api_key` - Anthropic API key (or set ANTHROPIC_API_KEY env var)
  - `:resume` - Session ID to resume a previous conversation
  - `:model` - Claude model to use
  - `:system_prompt` - Custom system prompt

  ## Examples

      # Start a basic session
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

      # Start with application config (if api_key is configured)
      {:ok, session} = ClaudeCode.start_link()

      # Resume a previous conversation
      {:ok, session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        resume: "previous-session-id"
      )

      # Start with custom options
      {:ok, session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        model: "opus",
        system_prompt: "You are an Elixir expert",
        allowed_tools: ["View", "Edit", "Bash(git:*)"],
        add_dir: ["/tmp", "/var/log"],
        max_turns: 20,
        timeout: 180_000,
        name: :my_session
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Session.start_link(opts)
  end

  @doc """
  Sends a query to Claude and waits for the complete response.

  This function blocks until Claude has finished responding. For streaming
  responses, use `query_stream/3` instead.

  ## Options

  Query-level options override session-level options. See `ClaudeCode.Options.query_schema/0`
  for all available query options.

  ## Examples

      {:ok, response} = ClaudeCode.query(session, "What is 2 + 2?")
      IO.puts(response)
      # => "4"

      # With option overrides
      {:ok, response} = ClaudeCode.query(session, "Complex query",
        system_prompt: "Focus on performance optimization",
        allowed_tools: ["View"],
        timeout: 120_000
      )
  """
  @spec query(session(), String.t(), keyword()) :: query_response()
  def query(session, prompt, opts \\ []) do
    # Extract timeout for GenServer.call, pass rest to session
    {timeout, query_opts} = Keyword.pop(opts, :timeout, 60_000)

    try do
      GenServer.call(session, {:query, prompt, query_opts}, timeout)
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout}
    end
  end

  @doc """
  Sends a query to Claude and returns a stream of messages.

  This function returns immediately with a stream that emits messages as they
  arrive from Claude. The stream will automatically complete when Claude finishes
  responding.

  ## Options

  Query-level options override session-level options. See `ClaudeCode.Options.query_schema/0`
  for all available query options.

  ## Examples

      # Stream all messages
      session
      |> ClaudeCode.query_stream("Write a hello world program")
      |> Enum.each(&IO.inspect/1)

      # Stream with option overrides
      session
      |> ClaudeCode.query_stream("Explain quantum computing",
           system_prompt: "Focus on practical applications",
           allowed_tools: ["View"])
      |> ClaudeCode.Stream.text_content()
      |> Enum.each(&IO.write/1)

      # Collect all text content
      text =
        session
        |> ClaudeCode.query_stream("Tell me a story")
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()
  """
  @spec query_stream(session(), String.t(), keyword()) :: message_stream()
  def query_stream(session, prompt, opts \\ []) do
    ClaudeCode.Stream.create(session, prompt, opts)
  end

  @doc """
  Sends a query to Claude asynchronously and returns a request ID.

  This function returns immediately with a request reference that can be used to
  track the query. Messages will be sent to the calling process as they arrive.

  ## Examples

      {:ok, request_ref} = ClaudeCode.query_async(session, "Complex task")

      # Receive messages for this request
      receive do
        {:claude_stream_started, ^request_ref} ->
          IO.puts("Started!")

        {:claude_message, ^request_ref, message} ->
          IO.inspect(message)

        {:claude_stream_end, ^request_ref} ->
          IO.puts("Done!")

        {:claude_stream_error, ^request_ref, error} ->
          IO.puts("Error: \#{inspect(error)}")
      end
  """
  @spec query_async(session(), String.t(), keyword()) :: {:ok, reference()} | {:error, term()}
  def query_async(session, prompt, opts \\ []) do
    GenServer.call(session, {:query_async, prompt, opts})
  end

  @doc """
  Stops a Claude Code session.

  This closes the CLI subprocess and cleans up resources.

  ## Examples

      :ok = ClaudeCode.stop(session)
  """
  @spec stop(session()) :: :ok
  def stop(session) do
    GenServer.stop(session)
  end

  @doc """
  Checks if a session is alive.

  ## Examples

      true = ClaudeCode.alive?(session)
  """
  @spec alive?(session()) :: boolean()
  def alive?(session) when is_atom(session) do
    case Process.whereis(session) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  def alive?(session) when is_pid(session) do
    Process.alive?(session)
  end

  @doc """
  Gets the current session ID for conversation continuity.

  Returns the session ID that Claude CLI is using to maintain conversation
  context. This ID is automatically captured from CLI responses and used
  for subsequent queries to continue the conversation.

  You can use this session ID with the `:resume` option when starting a
  new session to continue the conversation later.

  ## Examples

      {:ok, session_id} = ClaudeCode.get_session_id(session)
      # => {:ok, "abc123-session-id"}

      # For a new session with no queries yet
      {:ok, nil} = ClaudeCode.get_session_id(session)

      # Resume later
      {:ok, new_session} = ClaudeCode.start_link(resume: session_id)
  """
  @spec get_session_id(session()) :: {:ok, String.t() | nil}
  def get_session_id(session) do
    GenServer.call(session, :get_session_id)
  end

  @doc """
  Clears the current session ID to start a fresh conversation.

  This will cause the next query to start a new conversation context
  rather than continuing the existing one. Useful when you want to
  reset the conversation history.

  ## Examples

      :ok = ClaudeCode.clear(session)

      # Next query will start fresh
      {:ok, response} = ClaudeCode.query(session, "Hello!")
  """
  @spec clear(session()) :: :ok
  def clear(session) do
    GenServer.call(session, :clear_session)
  end

  # ==========================================================================
  # Advanced Streaming API
  # ==========================================================================

  @doc """
  Returns a Stream of all messages for a streaming request.

  Use this with `query_stream/3` when you need fine-grained control over
  message consumption. The stream yields messages as they arrive from the CLI.

  ## Examples

      {:ok, ref} = GenServer.call(session, {:query_stream, "Hello", []})

      session
      |> ClaudeCode.receive_messages(ref)
      |> Stream.each(&IO.inspect/1)
      |> Stream.run()
  """
  @spec receive_messages(session(), reference()) :: Enumerable.t()
  defdelegate receive_messages(session, req_ref), to: Session

  @doc """
  Returns a Stream of messages until a Result message is received.

  This is useful when you want to process all messages for a single turn
  and stop when Claude finishes responding.

  ## Examples

      {:ok, ref} = GenServer.call(session, {:query_stream, "Hello", []})

      session
      |> ClaudeCode.receive_response(ref)
      |> Stream.filter(&match?(%Message.Assistant{}, &1))
      |> Enum.each(&process_response/1)
  """
  @spec receive_response(session(), reference()) :: Enumerable.t()
  defdelegate receive_response(session, req_ref), to: Session

  @doc """
  Interrupts an in-progress request.

  Sends a SIGINT (Ctrl+C) to the CLI to interrupt the current operation.

  ## Examples

      {:ok, ref} = ClaudeCode.query_async(session, "Count to 1000 slowly")

      # Interrupt after some time
      Process.sleep(2000)
      :ok = ClaudeCode.interrupt(session, ref)
  """
  @spec interrupt(session(), reference()) :: :ok | {:error, term()}
  defdelegate interrupt(session, req_ref), to: Session
end
