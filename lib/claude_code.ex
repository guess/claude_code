defmodule ClaudeCode do
  @moduledoc """
  Elixir SDK for Claude Code CLI.

  This module provides the main interface for interacting with Claude Code
  through the command-line interface. It manages sessions as GenServer processes
  that maintain persistent CLI subprocesses for efficient bidirectional communication.

  ## API Overview

  | Function | Purpose |
  |----------|---------|
  | `start_link/1` | Start a session (with optional `resume: id`) |
  | `stop/1` | Stop a session |
  | `stream/3` | Send prompt to session, get message stream |
  | `query/2` | One-off query (auto start/stop) |

  ## Quick Start

      # Multi-turn conversation (primary API)
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

      ClaudeCode.stream(session, "What is 5 + 3?")
      |> Enum.each(&IO.inspect/1)

      ClaudeCode.stream(session, "Multiply that by 2")
      |> Enum.each(&IO.inspect/1)

      ClaudeCode.stop(session)

      # One-off query (convenience)
      {:ok, result} = ClaudeCode.query("What is 2 + 2?", api_key: "sk-ant-...")
      IO.puts(result)

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
      :code_reviewer
      |> ClaudeCode.stream("Review this function")
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()

  ## Resume Previous Conversations

      # Get session ID from a previous interaction
      {:ok, session_id} = ClaudeCode.get_session_id(session)

      # Later: resume the conversation
      {:ok, new_session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        resume: session_id
      )

      ClaudeCode.stream(new_session, "Continue where we left off")
      |> Enum.each(&IO.inspect/1)

  See `ClaudeCode.Supervisor` for advanced supervision patterns.
  """

  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Session

  @type session :: pid() | atom() | {:via, module(), any()}
  @type query_response ::
          {:ok, ResultMessage.t()} | {:error, ResultMessage.t() | term()}
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
  Sends a one-off query to Claude and returns the result.

  This is a convenience function that automatically manages a temporary session.
  For multi-turn conversations, use `start_link/1` and `stream/3` instead.

  ## Options

  See `ClaudeCode.Options.session_schema/0` for all available options.

  ## Examples

      # Simple one-off query
      {:ok, result} = ClaudeCode.query("What is 2 + 2?", api_key: "sk-ant-...")
      IO.puts(result)  # Result implements String.Chars
      # => "4"

      # With options
      {:ok, result} = ClaudeCode.query("Complex query",
        api_key: "sk-ant-...",
        model: "opus",
        system_prompt: "Focus on performance optimization"
      )

      # Handle errors
      case ClaudeCode.query("Do something risky", api_key: "sk-ant-...") do
        {:ok, result} -> IO.puts(result.result)
        {:error, %ClaudeCode.Message.ResultMessage{is_error: true} = result} ->
          IO.puts("Claude error: \#{result.result}")
        {:error, reason} -> IO.puts("Error: \#{inspect(reason)}")
      end
  """
  @spec query(String.t(), keyword()) :: query_response()
  def query(prompt, opts \\ []) do
    {:ok, session} = start_link(opts)

    try do
      session
      |> stream(prompt)
      |> collect_result()
    after
      stop(session)
    end
  end

  @doc """
  Sends a query to a session and returns a stream of messages.

  This is the primary API for interacting with Claude. The stream emits messages
  as they arrive and automatically completes when Claude finishes responding.

  ## Options

  Query-level options override session-level options. See `ClaudeCode.Options.query_schema/0`
  for all available query options.

  ## Examples

      # Stream all messages
      session
      |> ClaudeCode.stream("Write a hello world program")
      |> Enum.each(&IO.inspect/1)

      # Stream with option overrides
      session
      |> ClaudeCode.stream("Explain quantum computing",
           system_prompt: "Focus on practical applications",
           allowed_tools: ["View"])
      |> ClaudeCode.Stream.text_content()
      |> Enum.each(&IO.write/1)

      # Collect all text content
      text =
        session
        |> ClaudeCode.stream("Tell me a story")
        |> ClaudeCode.Stream.text_content()
        |> Enum.join()

      # Multi-turn conversation
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

      ClaudeCode.stream(session, "What is 5 + 3?")
      |> Enum.each(&IO.inspect/1)

      ClaudeCode.stream(session, "Multiply that by 2")
      |> Enum.each(&IO.inspect/1)
  """
  @spec stream(session(), String.t(), keyword()) :: message_stream()
  def stream(session, prompt, opts \\ []) do
    ClaudeCode.Stream.create(session, prompt, opts)
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

      # Next stream will start fresh
      ClaudeCode.stream(session, "Hello!")
      |> Enum.each(&IO.inspect/1)
  """
  @spec clear(session()) :: :ok
  def clear(session) do
    GenServer.call(session, :clear_session)
  end

  # Private helpers

  defp collect_result(stream) do
    stream
    |> Enum.reduce(nil, fn
      %ResultMessage{} = result, _acc -> result
      _msg, acc -> acc
    end)
    |> case do
      %ResultMessage{is_error: true} = result -> {:error, result}
      %ResultMessage{} = result -> {:ok, result}
      nil -> {:error, :no_result}
    end
  end
end
