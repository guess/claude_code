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

    * `:api_key` - Required. Your Anthropic API key
    * `:model` - Optional. The model to use (defaults to sonnet)
    * `:name` - Optional. A name to register the session under

  ## Examples

      # Start an unnamed session
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

      # Start a named session
      {:ok, session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
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

  ## Examples

      {:ok, response} = ClaudeCode.query_sync(session, "What is 2 + 2?")
      IO.puts(response)
      # => "4"

      # With a timeout
      {:ok, response} = ClaudeCode.query_sync(session, "Complex query", timeout: 60_000)
  """
  @spec query_sync(session(), String.t(), keyword()) :: query_response()
  def query_sync(session, prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    try do
      GenServer.call(session, {:query_sync, prompt, opts}, timeout)
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

    * `:timeout` - Maximum time to wait for each message (default: 60_000ms)
    * `:filter` - Message type filter (:all, :assistant, :tool_use, :result)

  ## Examples

      # Stream all messages
      session
      |> ClaudeCode.query("Write a hello world program")
      |> Enum.each(&IO.inspect/1)

      # Stream only assistant messages
      session
      |> ClaudeCode.query("Explain quantum computing", filter: :assistant)
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
