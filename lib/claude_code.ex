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
  | `health/1` | Check adapter health status |

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
      session_id = ClaudeCode.get_session_id(session)

      # Later: resume the conversation
      {:ok, new_session} = ClaudeCode.start_link(
        api_key: "sk-ant-...",
        resume: session_id
      )

      ClaudeCode.stream(new_session, "Continue where we left off")
      |> Enum.each(&IO.inspect/1)

      # Or fork to create a branch with a new session ID
      {:ok, forked} = ClaudeCode.start_link(
        resume: session_id,
        fork_session: true
      )

  See `ClaudeCode.Supervisor` for advanced supervision patterns.
  """

  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Session

  @doc """
  Returns the SDK version string.

  Used internally for environment variables passed to the CLI subprocess.

  ## Examples

      iex> ClaudeCode.version()
      "0.21.0"
  """
  @spec version() :: String.t()
  def version do
    :claude_code |> Application.spec(:vsn) |> to_string()
  end

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
  Returns the health status of the session's adapter.

  ## Examples

      :healthy = ClaudeCode.health(session)
      {:unhealthy, :port_dead} = ClaudeCode.health(session)
  """
  @spec health(session()) :: ClaudeCode.Adapter.health()
  def health(session) do
    GenServer.call(session, :health)
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
  new session to continue the conversation later, or with `:fork_session`
  to create a branch.

  ## Examples

      session_id = ClaudeCode.get_session_id(session)
      # => "abc123-session-id"

      # For a new session with no queries yet
      nil = ClaudeCode.get_session_id(session)

      # Resume later
      {:ok, new_session} = ClaudeCode.start_link(resume: session_id)

      # Or fork the conversation
      {:ok, forked} = ClaudeCode.start_link(resume: session_id, fork_session: true)
  """
  @spec get_session_id(session()) :: String.t() | nil
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

  @doc """
  Changes the model mid-conversation.

  ## Examples

      {:ok, _} = ClaudeCode.set_model(session, "claude-sonnet-4-5-20250929")
  """
  @spec set_model(session(), String.t()) :: {:ok, map()} | {:error, term()}
  def set_model(session, model) do
    GenServer.call(session, {:control, :set_model, %{model: model}})
  end

  @doc """
  Changes the permission mode mid-conversation.

  ## Examples

      {:ok, _} = ClaudeCode.set_permission_mode(session, :bypass_permissions)
  """
  @spec set_permission_mode(session(), atom()) :: {:ok, map()} | {:error, term()}
  def set_permission_mode(session, mode) do
    GenServer.call(session, {:control, :set_permission_mode, %{mode: mode}})
  end

  @doc """
  Queries MCP server connection status.

  ## Examples

      {:ok, %{"servers" => servers}} = ClaudeCode.get_mcp_status(session)
  """
  @spec get_mcp_status(session()) :: {:ok, map()} | {:error, term()}
  def get_mcp_status(session) do
    GenServer.call(session, {:control, :mcp_status, %{}})
  end

  @doc """
  Gets server initialization info cached from the control handshake.

  ## Examples

      {:ok, info} = ClaudeCode.get_server_info(session)
  """
  @spec get_server_info(session()) :: {:ok, map() | nil} | {:error, term()}
  def get_server_info(session) do
    GenServer.call(session, :get_server_info)
  end

  @doc """
  Interrupts the current generation.

  Sends an interrupt signal to the CLI to stop the current generation.
  This is a fire-and-forget operation — the CLI will stop generating
  and emit a result message.

  ## Examples

      :ok = ClaudeCode.interrupt(session)
  """
  @spec interrupt(session()) :: :ok | {:error, term()}
  def interrupt(session) do
    GenServer.call(session, :interrupt)
  end

  @doc """
  Rewinds tracked files to the state at a specific user message checkpoint.

  ## Examples

      {:ok, _} = ClaudeCode.rewind_files(session, "user-msg-uuid-123")
  """
  @spec rewind_files(session(), String.t()) :: {:ok, map()} | {:error, term()}
  def rewind_files(session, user_message_id) do
    GenServer.call(session, {:control, :rewind_files, %{user_message_id: user_message_id}})
  end

  @doc """
  Reads conversation history from a session's JSONL file.

  Accepts either a session ID string or a running session reference.
  Returns user and assistant messages parsed into SDK message structs.

  ## Options

  - `:project_path` - Specific project path to search in (optional)
  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      # Read conversation history by session ID
      {:ok, messages} = ClaudeCode.conversation("abc123-def456")

      # Or from a running session
      {:ok, session} = ClaudeCode.start_link()
      ClaudeCode.query(session, "Hello!")
      {:ok, messages} = ClaudeCode.conversation(session)

      Enum.each(messages, fn
        %ClaudeCode.Message.UserMessage{message: %{content: content}} ->
          IO.puts("User: \#{inspect(content)}")
        %ClaudeCode.Message.AssistantMessage{message: %{content: blocks}} ->
          text = Enum.map_join(blocks, "", fn
            %ClaudeCode.Content.TextBlock{text: t} -> t
            _ -> ""
          end)
          IO.puts("Assistant: \#{text}")
      end)

  See `ClaudeCode.History` for more options.
  """
  @spec conversation(session() | String.t(), keyword()) ::
          {:ok, [ClaudeCode.Message.AssistantMessage.t() | ClaudeCode.Message.UserMessage.t()]}
          | {:error, term()}
  def conversation(session_or_id, opts \\ [])

  def conversation(session_id, opts) when is_binary(session_id) do
    ClaudeCode.History.conversation(session_id, opts)
  end

  def conversation(session, opts) do
    case get_session_id(session) do
      nil -> {:error, :no_session_id}
      session_id -> ClaudeCode.History.conversation(session_id, opts)
    end
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
