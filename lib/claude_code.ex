defmodule ClaudeCode do
  @moduledoc """
  Elixir SDK for Claude Code CLI.

  This module provides the main interface for interacting with Claude Code
  through the command-line interface. It manages sessions as GenServer processes
  that communicate with the Claude CLI via JSON streaming over stdout.

  ## Example

      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")
      {:ok, response} = ClaudeCode.query_sync(session, "Hello, Claude!")
      IO.puts(response.content)
  """

  alias ClaudeCode.Session

  @type session :: pid() | atom() | {:via, module(), any()}
  @type query_response :: {:ok, String.t()} | {:error, term()}
  @type message_stream :: Enumerable.t(ClaudeCode.Message.t())

  @doc """
  Starts a new Claude Code session.

  ## Options

  For complete option documentation including types, validation rules, and examples,
  see `ClaudeCode.Options.session_schema/0` and the `ClaudeCode.Options` module.

  ## Examples

      # Start a basic session
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

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
  def start_link(opts) do
    Session.start_link(opts)
  end

  @doc """
  Sends a synchronous query to Claude and waits for the complete response.

  This function blocks until Claude has finished responding. For streaming
  responses, use `query/3` instead.

  ## Options

  Query-level options override session-level options. See `ClaudeCode.Options.query_schema/0`
  for all available query options.

  ## Examples

      {:ok, response} = ClaudeCode.query_sync(session, "What is 2 + 2?")
      IO.puts(response)
      # => "4"

      # With option overrides
      {:ok, response} = ClaudeCode.query_sync(session, "Complex query", 
        system_prompt: "Focus on performance optimization",
        allowed_tools: ["View"],
        timeout: 120_000
      )
  """
  @spec query_sync(session(), String.t(), keyword()) :: query_response()
  def query_sync(session, prompt, opts \\ []) do
    # Extract timeout for GenServer.call, pass rest to session
    {timeout, query_opts} = Keyword.pop(opts, :timeout, 60_000)

    try do
      GenServer.call(session, {:query_sync, prompt, query_opts}, timeout)
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
      |> ClaudeCode.query("Write a hello world program")
      |> Enum.each(&IO.inspect/1)

      # Stream with option overrides
      session
      |> ClaudeCode.query("Explain quantum computing", 
           system_prompt: "Focus on practical applications",
           allowed_tools: ["View"])
      |> ClaudeCode.Stream.text_content()
      |> Enum.each(&IO.write/1)

      # Collect all text content
      text = 
        session
        |> ClaudeCode.query("Tell me a story")
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()
  """
  @spec query(session(), String.t(), keyword()) :: message_stream()
  def query(session, prompt, opts \\ []) do
    ClaudeCode.Stream.create(session, prompt, opts)
  end

  @doc """
  Sends a query to Claude asynchronously and returns a request ID.

  This function returns immediately with a request ID that can be used to
  track the query. Use `receive_message/2` to get messages for a specific
  request.

  ## Examples

      {:ok, request_id} = ClaudeCode.query_async(session, "Complex task")
      
      # Later, receive messages for this request
      receive do
        {:claude_message, ^request_id, message} ->
          IO.inspect(message)
      end
  """
  @spec query_async(session(), String.t(), keyword()) :: {:ok, reference()} | {:error, term()}
  def query_async(session, prompt, opts \\ []) do
    GenServer.call(session, {:query_async, prompt, opts})
  end

  @doc """
  Stops a Claude Code session.

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

  ## Examples

      {:ok, session_id} = ClaudeCode.get_session_id(session)
      # => {:ok, "abc123-session-id"}
      
      # For a new session with no queries yet
      {:ok, nil} = ClaudeCode.get_session_id(session)
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

      :ok = ClaudeCode.clear_session(session)
      
      # Next query will start fresh
      {:ok, response} = ClaudeCode.query_sync(session, "Hello!")
  """
  @spec clear_session(session()) :: :ok
  def clear_session(session) do
    GenServer.call(session, :clear_session)
  end
end
