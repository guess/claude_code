defmodule ClaudeCode.Supervisor do
  @moduledoc """
  Supervisor for managing multiple ClaudeCode sessions.

  This supervisor allows you to start and manage multiple named Claude sessions
  in your application's supervision tree, providing fault tolerance and automatic
  restart capabilities.

  ## Examples

  ### Basic usage with predefined sessions

      children = [
        {ClaudeCode.Supervisor, [
          [name: :code_reviewer, api_key: api_key, system_prompt: "You are an expert code reviewer"],
          [name: :test_writer, api_key: api_key, system_prompt: "You write comprehensive tests"]
        ]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  ### Using global names for distributed access

      children = [
        {ClaudeCode.Supervisor, [
          [name: {:global, :main_assistant}, api_key: api_key],
          [name: {:via, Registry, {MyApp.Registry, :helper}}, api_key: api_key]
        ]}
      ]

  ### Dynamic session management

      # Start the supervisor without initial sessions
      {:ok, supervisor} = ClaudeCode.Supervisor.start_link([])

      # Add sessions dynamically
      ClaudeCode.Supervisor.start_session(supervisor, [
        name: :dynamic_session,
        api_key: api_key,
        system_prompt: "Dynamic helper"
      ])

      # Remove sessions when no longer needed
      ClaudeCode.Supervisor.terminate_session(supervisor, :dynamic_session)

  ## Session Access

  Once supervised, sessions can be accessed by name from anywhere in your application:

      # Query a supervised session
      {:ok, response} = ClaudeCode.query(:code_reviewer, "Review this function")

      # Stream from a supervised session
      :test_writer
      |> ClaudeCode.query_stream("Write tests for UserController")
      |> Stream.each(&IO.inspect/1)
      |> Stream.run()

  ## Fault Tolerance

  If a session crashes, the supervisor will automatically restart it:
  - Session state is lost but the process name is preserved
  - Conversation history is cleared on restart
  - Other sessions continue running unaffected

  ## Configuration

  Sessions inherit application configuration and can override specific options:

      # config/config.exs
      config :claude_code,
        model: "opus",
        stream_timeout: :infinity

      # Supervisor sessions automatically use app config
      {ClaudeCode.Supervisor, [
        [name: :assistant, api_key: api_key],  # Uses app config defaults
        [name: :writer, api_key: api_key, model: "sonnet"]  # Overrides model
      ]}
  """

  use Supervisor

  @doc """
  Starts the ClaudeCode supervisor.

  ## Arguments

  - `sessions` - List of session configurations. Each session config is a keyword list
    of options passed to `ClaudeCode.Session.start_link/1`.

  ## Options

  - `:name` - Name for the supervisor process (optional)
  - `:strategy` - Supervision strategy (defaults to `:one_for_one`)
  - `:max_restarts` - Maximum restarts allowed (defaults to `3`)
  - `:max_seconds` - Time window for max restarts (defaults to `5`)

  ## Examples

      # Start with predefined sessions
      {:ok, sup} = ClaudeCode.Supervisor.start_link([
        [name: :assistant, api_key: "sk-ant-..."],
        [name: :reviewer, api_key: "sk-ant-...", system_prompt: "Review code"]
      ])

      # Start empty supervisor for dynamic management
      {:ok, sup} = ClaudeCode.Supervisor.start_link([])

      # Start with custom supervisor options
      {:ok, sup} = ClaudeCode.Supervisor.start_link(
        [
          [name: :assistant, api_key: "sk-ant-..."]
        ],
        name: MyApp.ClaudeSupervisor,
        max_restarts: 5,
        max_seconds: 10
      )
  """
  def start_link(sessions, opts \\ []) do
    {supervisor_opts, _session_opts} = extract_supervisor_options(opts)
    supervisor_name = supervisor_opts[:name]

    case supervisor_name do
      nil ->
        Supervisor.start_link(__MODULE__, {sessions, supervisor_opts})

      name ->
        Supervisor.start_link(__MODULE__, {sessions, supervisor_opts}, name: name)
    end
  end

  @doc """
  Dynamically starts a new session under the supervisor.

  ## Arguments

  - `supervisor` - PID or name of the ClaudeCode.Supervisor
  - `session_config` - Keyword list of session options

  ## Examples

      ClaudeCode.Supervisor.start_session(supervisor, [
        name: :new_assistant,
        api_key: api_key,
        system_prompt: "You are helpful"
      ])

      # With custom child ID
      ClaudeCode.Supervisor.start_session(supervisor, [
        name: :temp_session,
        api_key: api_key
      ], id: :my_temp_session)
  """
  def start_session(supervisor, session_config, opts \\ []) do
    child_id = opts[:id] || session_config[:name] || make_ref()

    child_spec = %{
      id: child_id,
      start: {ClaudeCode.Session, :start_link, [session_config]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }

    Supervisor.start_child(supervisor, child_spec)
  end

  @doc """
  Terminates a session managed by the supervisor.

  ## Arguments

  - `supervisor` - PID or name of the ClaudeCode.Supervisor  
  - `session_id` - Child ID or session name

  ## Examples

      ClaudeCode.Supervisor.terminate_session(supervisor, :old_session)
  """
  def terminate_session(supervisor, session_id) do
    Supervisor.terminate_child(supervisor, session_id)
    Supervisor.delete_child(supervisor, session_id)
  end

  @doc """
  Lists all sessions currently managed by the supervisor.

  Returns a list of `{child_id, child_pid, type, modules}` tuples.

  ## Examples

      sessions = ClaudeCode.Supervisor.list_sessions(supervisor)
      #=> [{:assistant, #PID<0.123.0>, :worker, [ClaudeCode.Session]}]
  """
  def list_sessions(supervisor) do
    Supervisor.which_children(supervisor)
  end

  @doc """
  Gets the count of sessions managed by the supervisor.

  ## Examples

      count = ClaudeCode.Supervisor.count_sessions(supervisor)
      #=> 3
  """
  def count_sessions(supervisor) do
    supervisor
    |> Supervisor.count_children()
    |> Map.get(:active, 0)
  end

  @doc """
  Restarts a specific session.

  This will terminate the current session process and start a new one with the same configuration.
  Note that conversation history will be lost.

  ## Examples

      :ok = ClaudeCode.Supervisor.restart_session(supervisor, :assistant)
  """
  def restart_session(supervisor, session_id) do
    case Supervisor.restart_child(supervisor, session_id) do
      {:ok, _child} -> :ok
      {:ok, _child, _info} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Supervisor Callbacks

  @impl true
  def init({sessions, supervisor_opts}) do
    # Extract supervision strategy options
    strategy = supervisor_opts[:strategy] || :one_for_one
    max_restarts = supervisor_opts[:max_restarts] || 3
    max_seconds = supervisor_opts[:max_seconds] || 5

    # Build child specifications
    children = Enum.map(sessions, &build_child_spec/1)

    Supervisor.init(children,
      strategy: strategy,
      max_restarts: max_restarts,
      max_seconds: max_seconds
    )
  end

  # Private Functions

  defp extract_supervisor_options(opts) do
    supervisor_keys = [:name, :strategy, :max_restarts, :max_seconds]
    {supervisor_opts, _session_opts} = Keyword.split(opts, supervisor_keys)
    {supervisor_opts, []}
  end

  defp build_child_spec(session_config) do
    # Use explicit id, then session name, then unique reference as child ID
    child_id = session_config[:id] || session_config[:name] || make_ref()

    %{
      id: child_id,
      start: {ClaudeCode.Session, :start_link, [session_config]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end
end
