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
  Starts a new Claude Code session with flattened options.

  ## Options

    * `:api_key` - Required. Your Anthropic API key
    * `:model` - Optional. The model to use (defaults to "sonnet")
    * `:system_prompt` - Optional. System prompt for Claude
    * `:allowed_tools` - Optional. List of allowed tools (e.g. ["View", "Bash(git:*)"])
    * `:max_conversation_turns` - Optional. Max conversation turns (default: 50)
    * `:working_directory` - Optional. Working directory for file operations
    * `:timeout` - Optional. Query timeout in ms (default: 300_000)
    * `:name` - Optional. A name to register the session under

  ## Examples

      # Start a basic session
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

      # Start with custom options
      {:ok, session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        system_prompt: "You are an Elixir expert",
        allowed_tools: ["View", "GlobTool", "Bash(git:*)"],
        max_conversation_turns: 20,
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

  Query-level options override session-level options:

    * `:system_prompt` - Override system prompt for this query
    * `:timeout` - Override timeout for this query
    * `:allowed_tools` - Override allowed tools for this query

  ## Examples

      {:ok, response} = ClaudeCode.query_sync(session, "What is 2 + 2?")
      IO.puts(response)
      # => "4"

      # With overrides
      {:ok, response} = ClaudeCode.query_sync(session, "Complex query", 
        system_prompt: "Focus on performance optimization",
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

  Query-level options override session-level options:

    * `:system_prompt` - Override system prompt for this query
    * `:timeout` - Override timeout for this query  
    * `:allowed_tools` - Override allowed tools for this query
    * `:filter` - Message type filter (:all, :assistant, :tool_use, :result)

  ## Examples

      # Stream all messages
      session
      |> ClaudeCode.query("Write a hello world program")
      |> Enum.each(&IO.inspect/1)

      # Stream with option overrides
      session
      |> ClaudeCode.query("Explain quantum computing", 
           system_prompt: "Focus on practical applications",
           filter: :assistant)
      |> Stream.map(& &1.message.content)
      |> Stream.flat_map(&Function.identity/1)
      |> Enum.each(&IO.inspect/1)

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
end
