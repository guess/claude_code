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

  @doc """
  Starts a new Claude Code session.

  ## Options

    * `:api_key` - Required. Your Anthropic API key
    * `:model` - Optional. The model to use (defaults to claude-3-5-haiku-20241022)
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
  responses, use `query/3` instead (to be implemented in Phase 3).

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
