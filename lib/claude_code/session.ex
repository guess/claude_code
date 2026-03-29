defmodule ClaudeCode.Session do
  @moduledoc """
  Public API for interacting with Claude Code sessions.

  This module provides functions for managing session lifecycle, runtime
  configuration, MCP server management, and introspection. For the basic
  "getting started" API, see `ClaudeCode`.

  ## Session Lifecycle

      {:ok, session} = ClaudeCode.Session.start_link(api_key: "sk-ant-...")

      ClaudeCode.Session.stream(session, "What is 5 + 3?")
      |> Enum.each(&IO.inspect/1)

      ClaudeCode.Session.stop(session)

  ## Runtime Configuration

      :ok = ClaudeCode.Session.set_model(session, "claude-sonnet-4-5-20250929")
      :ok = ClaudeCode.Session.set_permission_mode(session, :accept_edits)

  ## MCP Server Management

      {:ok, servers} = ClaudeCode.Session.mcp_status(session)
      :ok = ClaudeCode.Session.mcp_reconnect(session, "my-server")

  ## Introspection

      {:ok, info} = ClaudeCode.Session.server_info(session)
      {:ok, models} = ClaudeCode.Session.supported_models(session)
  """

  alias ClaudeCode.CLI.Control.Types

  @type session :: pid() | atom() | {:via, module(), any()}

  # ============================================================================
  # Lifecycle
  # ============================================================================

  @doc """
  Starts a new Claude Code session.

  See `ClaudeCode.start_link/1` for full documentation and examples.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    __MODULE__.Server.start_link(opts)
  end

  @doc """
  Sends a query to a session and returns a stream of messages.

  See `ClaudeCode.stream/3` for full documentation and examples.
  """
  @spec stream(session(), String.t(), keyword()) :: Enumerable.t(ClaudeCode.Message.t())
  def stream(session, prompt, opts \\ []) do
    ClaudeCode.Stream.create(session, prompt, opts)
  end

  @doc """
  Stops a Claude Code session.

  This closes the CLI subprocess and cleans up resources.

  ## Examples

      :ok = ClaudeCode.Session.stop(session)
  """
  @spec stop(session()) :: :ok
  def stop(session) do
    GenServer.stop(session)
  end

  # ============================================================================
  # Session State
  # ============================================================================

  @doc """
  Returns the health status of the session's adapter.

  ## Examples

      :healthy = ClaudeCode.Session.health(session)
      {:unhealthy, :port_dead} = ClaudeCode.Session.health(session)
  """
  @spec health(session()) :: ClaudeCode.Adapter.health()
  def health(session) do
    GenServer.call(session, :health)
  end

  @doc """
  Checks if a session is alive.

  ## Examples

      true = ClaudeCode.Session.alive?(session)
  """
  @spec alive?(session()) :: boolean()
  def alive?(session) when is_pid(session), do: Process.alive?(session)
  def alive?(session) when is_atom(session), do: GenServer.whereis(session) != nil
  def alive?({:via, _, _} = session), do: GenServer.whereis(session) != nil

  @doc """
  Gets the current session ID for conversation continuity.

  Returns the session ID that Claude CLI is using to maintain conversation
  context. This ID is automatically captured from CLI responses and used
  for subsequent queries to continue the conversation.

  You can use this session ID with the `:resume` option when starting a
  new session to continue the conversation later, or with `:fork_session`
  to create a branch.

  ## Examples

      session_id = ClaudeCode.Session.session_id(session)
      # => "abc123-session-id"

      # For a new session with no queries yet
      nil = ClaudeCode.Session.session_id(session)

      # Resume later
      {:ok, new_session} = ClaudeCode.start_link(resume: session_id)

      # Or fork the conversation
      {:ok, forked} = ClaudeCode.start_link(resume: session_id, fork_session: true)
  """
  @spec session_id(session()) :: String.t() | nil
  def session_id(session) do
    GenServer.call(session, :get_session_id)
  end

  @doc """
  Clears the current session ID to start a fresh conversation.

  This will cause the next query to start a new conversation context
  rather than continuing the existing one. Useful when you want to
  reset the conversation history.

  ## Examples

      :ok = ClaudeCode.Session.clear(session)

      # Next stream will start fresh
      ClaudeCode.Session.stream(session, "Hello!")
      |> Enum.each(&IO.inspect/1)
  """
  @spec clear(session()) :: :ok
  def clear(session) do
    GenServer.call(session, :clear_session)
  end

  @doc """
  Interrupts the current generation.

  Sends an interrupt signal to the CLI to stop the current generation.
  This is a fire-and-forget operation — the CLI will stop generating
  and emit a result message.

  ## Examples

      :ok = ClaudeCode.Session.interrupt(session)
  """
  @spec interrupt(session()) :: :ok | {:error, term()}
  def interrupt(session) do
    GenServer.call(session, :interrupt)
  end

  # ============================================================================
  # Runtime Configuration
  # ============================================================================

  @doc """
  Changes the model mid-conversation.

  ## Examples

      :ok = ClaudeCode.Session.set_model(session, "claude-sonnet-4-5-20250929")
  """
  @spec set_model(session(), String.t()) :: :ok | {:error, term()}
  def set_model(session, model) do
    session |> GenServer.call({:control, :set_model, %{model: model}}) |> to_ok()
  end

  @doc """
  Changes the permission mode mid-conversation.

  ## Examples

      :ok = ClaudeCode.Session.set_permission_mode(session, :bypass_permissions)
  """
  @spec set_permission_mode(session(), atom()) :: :ok | {:error, term()}
  def set_permission_mode(session, mode) do
    session |> GenServer.call({:control, :set_permission_mode, %{mode: mode}}) |> to_ok()
  end

  # ============================================================================
  # MCP Management
  # ============================================================================

  @doc """
  Queries MCP server connection status.

  ## Examples

      {:ok, servers} = ClaudeCode.Session.mcp_status(session)
      Enum.each(servers, &IO.puts(&1.name))
  """
  @spec mcp_status(session()) :: {:ok, [ClaudeCode.MCP.Status.t()]} | {:error, term()}
  def mcp_status(session) do
    GenServer.call(session, {:control, :mcp_status, %{}})
  end

  @doc """
  Returns a breakdown of current context window usage by category.

  The result is a map with keys like `"categories"`, `"total_tokens"`,
  `"max_tokens"`, `"percentage"`, `"model"`, etc.

  ## Examples

      {:ok, usage} = ClaudeCode.Session.get_context_usage(session)
  """
  @spec get_context_usage(session()) :: {:ok, map()} | {:error, term()}
  def get_context_usage(session) do
    GenServer.call(session, {:control, :get_context_usage, %{}})
  end

  @doc """
  Reloads plugins from disk and returns refreshed session components.

  The result is a map with `"commands"`, `"agents"`, `"plugins"`,
  `"mcp_servers"`, and `"error_count"` keys.

  ## Examples

      {:ok, result} = ClaudeCode.Session.reload_plugins(session)
  """
  @spec reload_plugins(session()) :: {:ok, map()} | {:error, term()}
  def reload_plugins(session) do
    GenServer.call(session, {:control, :reload_plugins, %{}})
  end

  @doc """
  Reconnects a disconnected or failed MCP server.

  ## Examples

      :ok = ClaudeCode.Session.mcp_reconnect(session, "my-server")
  """
  @spec mcp_reconnect(session(), String.t()) :: :ok | {:error, term()}
  def mcp_reconnect(session, server_name) do
    session |> GenServer.call({:control, :mcp_reconnect, %{server_name: server_name}}) |> to_ok()
  end

  @doc """
  Enables or disables an MCP server.

  ## Examples

      :ok = ClaudeCode.Session.mcp_toggle(session, "my-server", false)
  """
  @spec mcp_toggle(session(), String.t(), boolean()) :: :ok | {:error, term()}
  def mcp_toggle(session, server_name, enabled) do
    session
    |> GenServer.call({:control, :mcp_toggle, %{server_name: server_name, enabled: enabled}})
    |> to_ok()
  end

  @doc """
  Replaces the set of dynamically managed MCP servers.

  ## Examples

      {:ok, _} = ClaudeCode.Session.set_mcp_servers(session, %{"tools" => %{"type" => "stdio", "command" => "npx"}})
  """
  @spec set_mcp_servers(session(), map()) :: {:ok, Types.set_servers_result()} | {:error, term()}
  def set_mcp_servers(session, servers) do
    GenServer.call(session, {:control, :set_mcp_servers, %{servers: servers}})
  end

  # ============================================================================
  # Introspection
  # ============================================================================

  @doc """
  Gets server initialization info cached from the control handshake.

  ## Examples

      {:ok, info} = ClaudeCode.Session.server_info(session)
  """
  @spec server_info(session()) :: {:ok, Types.initialize_response() | nil} | {:error, term()}
  def server_info(session) do
    GenServer.call(session, :get_server_info)
  end

  @doc """
  Returns the list of available commands from the initialization response.

  ## Examples

      {:ok, commands} = ClaudeCode.Session.supported_commands(session)
      Enum.each(commands, &IO.puts(&1.name))
  """
  @spec supported_commands(session()) :: {:ok, [ClaudeCode.Session.SlashCommand.t()]} | {:error, term()}
  def supported_commands(session), do: extract_server_info_list(session, :commands)

  @doc """
  Returns the list of available models from the initialization response.

  ## Examples

      {:ok, models} = ClaudeCode.Session.supported_models(session)
      Enum.each(models, &IO.puts(&1.display_name))
  """
  @spec supported_models(session()) :: {:ok, [ClaudeCode.Model.Info.t()]} | {:error, term()}
  def supported_models(session), do: extract_server_info_list(session, :models)

  @doc """
  Returns the list of available subagents from the initialization response.

  ## Examples

      {:ok, agents} = ClaudeCode.Session.supported_agents(session)
  """
  @spec supported_agents(session()) :: {:ok, [ClaudeCode.Session.AgentInfo.t()]} | {:error, term()}
  def supported_agents(session), do: extract_server_info_list(session, :agents)

  @doc """
  Returns account information from the initialization response.

  ## Examples

      {:ok, account} = ClaudeCode.Session.account_info(session)
      IO.puts(account.email)
  """
  @spec account_info(session()) :: {:ok, ClaudeCode.Session.AccountInfo.t() | nil} | {:error, term()}
  def account_info(session) do
    case server_info(session) do
      {:ok, %{account: account}} -> {:ok, account}
      {:ok, _} -> {:ok, nil}
      error -> error
    end
  end

  # ============================================================================
  # History
  # ============================================================================

  @doc """
  Reads conversation messages for the current session.

  Routes through the session server so History reads execute on the
  correct node (local for Port, remote for Node adapter). Returns
  `{:ok, []}` if no session ID has been captured yet (no queries made).

  For local-only access by session ID string, use
  `ClaudeCode.History.get_messages/2` directly.

  ## Options

  - `:project_path` - Project directory to find the session in
  - `:limit` - Maximum number of messages to return
  - `:offset` - Number of messages to skip from the start (default: 0)
  - `:claude_dir` - Override the Claude directory (default: `~/.claude`)

  ## Examples

      {:ok, session} = ClaudeCode.start_link()
      ClaudeCode.Session.stream(session, "Hello!") |> Stream.run()
      {:ok, messages} = ClaudeCode.Session.get_messages(session)

      # With pagination
      {:ok, page} = ClaudeCode.Session.get_messages(session, limit: 10, offset: 5)

  See `ClaudeCode.History.get_messages/2` for more details.
  """
  @spec get_messages(session(), keyword()) ::
          {:ok, [ClaudeCode.History.SessionMessage.t()]} | {:error, term()}
  def get_messages(session, opts \\ []) do
    GenServer.call(session, {:history_call, :get_messages, opts})
  end

  @doc """
  Lists sessions with rich metadata from the adapter's node.

  Automatically injects `:project_path` from the session's `:cwd` option
  if not provided. When `:project_path` is set, returns sessions for that
  project directory. When omitted, returns sessions across all projects.

  For local-only access, use `ClaudeCode.History.list_sessions/1` directly.

  ## Options

  - `:project_path` - Project directory to list sessions for (default: session cwd)
  - `:limit` - Maximum number of sessions to return
  - `:include_worktrees` - Scan git worktrees (default: `true`)
  - `:claude_dir` - Override `~/.claude` (for testing)

  ## Examples

      {:ok, sessions} = ClaudeCode.Session.list_sessions(session)
      {:ok, recent} = ClaudeCode.Session.list_sessions(session, limit: 10)

  See `ClaudeCode.History.list_sessions/1` for more details.
  """
  @spec list_sessions(session(), keyword()) :: {:ok, [ClaudeCode.History.SessionInfo.t()]}
  def list_sessions(session, opts \\ []) do
    GenServer.call(session, {:history_list, opts})
  end

  # ============================================================================
  # Remote Execution
  # ============================================================================

  @doc """
  Executes an arbitrary function call on the adapter's node.

  Runs `apply(module, function, args)` on whatever node the adapter lives on.
  For local adapters (Port), this is equivalent to a direct `apply`. For
  distributed adapters (Node), this dispatches via `:rpc.call`.

  ## Examples

      # Read a file on the adapter's node
      {:ok, contents} = ClaudeCode.Session.execute(session, File, :read, ["/workspace/config.json"])

      # List directory on the adapter's node
      {:ok, files} = ClaudeCode.Session.execute(session, File, :ls, ["/workspace"])

      # Run a custom module function
      result = ClaudeCode.Session.execute(session, MyApp.Sandbox, :cleanup, [workspace_id])
  """
  @spec execute(session(), module(), atom(), [term()]) :: term()
  def execute(session, module, function, args) do
    GenServer.call(session, {:adapter_call, module, function, args})
  end

  # ============================================================================
  # Tasks
  # ============================================================================

  @doc """
  Stops a running task.

  A task_notification with status 'stopped' will be emitted.

  ## Examples

      :ok = ClaudeCode.Session.stop_task(session, "task-id-123")
  """
  @spec stop_task(session(), String.t()) :: :ok | {:error, term()}
  def stop_task(session, task_id) do
    session |> GenServer.call({:control, :stop_task, %{task_id: task_id}}) |> to_ok()
  end

  @doc """
  Seeds the CLI's file read state cache.

  Use after a Read result has been compacted out of context to prevent
  Edit validation failures. The `mtime` lets the CLI detect if the file
  changed since the seeded Read.

  ## Parameters

    * `session` - Session reference
    * `path` - File path to seed
    * `mtime` - File modification time (Unix timestamp)

  ## Examples

      :ok = ClaudeCode.Session.seed_read_state(session, "/path/to/file.ex", 1_711_700_000)
  """
  @spec seed_read_state(session(), String.t(), integer()) :: :ok | {:error, term()}
  def seed_read_state(session, path, mtime) do
    session
    |> GenServer.call({:control, :seed_read_state, %{path: path, mtime: mtime}})
    |> to_ok()
  end

  # ============================================================================
  # File Checkpointing
  # ============================================================================

  @doc """
  Rewinds tracked files to the state at a specific user message checkpoint.

  ## Options

    * `:dry_run` - When `true`, preview changes without applying them (default: `false`)

  ## Examples

      {:ok, _} = ClaudeCode.Session.rewind_files(session, "user-msg-uuid-123")

      # Preview changes without applying
      {:ok, preview} = ClaudeCode.Session.rewind_files(session, "user-msg-uuid-123", dry_run: true)
  """
  @spec rewind_files(session(), String.t(), keyword()) :: {:ok, Types.rewind_files_result()} | {:error, term()}
  def rewind_files(session, user_message_id, opts \\ []) do
    params = maybe_put_opt(%{user_message_id: user_message_id}, :dry_run, opts)

    GenServer.call(session, {:control, :rewind_files, params})
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp extract_server_info_list(session, key) do
    case server_info(session) do
      {:ok, %{^key => list}} when is_list(list) -> {:ok, list}
      {:ok, _} -> {:ok, []}
      error -> error
    end
  end

  defp to_ok({:ok, _}), do: :ok
  defp to_ok({:error, _} = error), do: error

  defp maybe_put_opt(map, key, opts) do
    case Keyword.get(opts, key) do
      nil -> map
      value -> Map.put(map, key, value)
    end
  end
end
