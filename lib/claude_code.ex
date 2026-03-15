defmodule ClaudeCode do
  @moduledoc """
  Elixir SDK for Claude Code CLI.

  This module provides the main entry points for interacting with Claude Code.
  For session management, runtime configuration, and introspection, see
  `ClaudeCode.Session`.

  ## API Overview

  | Function | Purpose |
  |----------|---------|
  | `start_link/1` | Start a session |
  | `stream/3` | Send prompt, get message stream |
  | `query/2` | One-off query (auto start/stop) |
  | `stop/1` | Stop a session |

  ## Quick Start

      # Multi-turn conversation
      {:ok, session} = ClaudeCode.start_link(api_key: "sk-ant-...")

      ClaudeCode.stream(session, "What is 5 + 3?")
      |> Enum.each(&IO.inspect/1)

      ClaudeCode.stream(session, "Multiply that by 2")
      |> Enum.each(&IO.inspect/1)

      ClaudeCode.stop(session)

      # One-off query (convenience)
      {:ok, result} = ClaudeCode.query("What is 2 + 2?", api_key: "sk-ant-...")
      IO.puts(result)

  ## Supervision for Production

      children = [
        {ClaudeCode.Supervisor, [
          [name: :code_reviewer, api_key: api_key, system_prompt: "You review Elixir code"],
          [name: :test_writer, api_key: api_key, system_prompt: "You write ExUnit tests"]
        ]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      :code_reviewer
      |> ClaudeCode.stream("Review this function")
      |> ClaudeCode.Stream.text_content()
      |> Enum.join()

  ## Resume Previous Conversations

      session_id = ClaudeCode.Session.session_id(session)

      {:ok, new_session} = ClaudeCode.start_link(resume: session_id)

      ClaudeCode.stream(new_session, "Continue where we left off")
      |> Enum.each(&IO.inspect/1)

  See `ClaudeCode.Session` for runtime configuration, MCP management,
  and introspection functions. See `ClaudeCode.Supervisor` for advanced
  supervision patterns.
  """

  alias ClaudeCode.Adapter.Port.Installer
  alias ClaudeCode.Message.ResultMessage

  @doc """
  Returns the SDK version string.

  ## Examples

      iex> ClaudeCode.version()
      "0.33.0"
  """
  @spec version() :: String.t()
  def version do
    :claude_code |> Application.spec(:vsn) |> to_string()
  end

  @doc """
  Returns the configured CLI version.

  This is the Claude Code CLI version the SDK is configured to use.
  It can be overridden via application config (`:cli_version`), otherwise
  defaults to the version the SDK was tested against.

  ## Examples

      iex> ClaudeCode.cli_version()
      "2.1.76"
  """
  @spec cli_version() :: String.t()
  def cli_version do
    Installer.configured_version()
  end

  @type session :: ClaudeCode.Session.session()
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
        timeout: :infinity,
        name: :my_session
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    ClaudeCode.Session.start_link(opts)
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
    ClaudeCode.Session.stream(session, prompt, opts)
  end

  @doc """
  Stops a Claude Code session.

  This closes the CLI subprocess and cleans up resources.

  ## Examples

      :ok = ClaudeCode.stop(session)
  """
  @spec stop(session()) :: :ok
  def stop(session) do
    ClaudeCode.Session.stop(session)
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
