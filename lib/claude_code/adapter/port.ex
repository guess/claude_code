defmodule ClaudeCode.Adapter.Port do
  @moduledoc """
  Local CLI adapter that manages a persistent Port connection to the Claude CLI.

  This adapter:
  - Spawns the CLI subprocess with `--input-format stream-json`
  - Receives async messages from the Port
  - Forwards raw decoded JSON maps to Session for parsing
  - Handles Port lifecycle (connect, reconnect, cleanup)
  """

  @behaviour ClaudeCode.Adapter

  use GenServer

  alias ClaudeCode.Adapter
  alias ClaudeCode.Adapter.ControlHandler
  alias ClaudeCode.Adapter.Port.Installer
  alias ClaudeCode.Adapter.Port.Resolver
  alias ClaudeCode.CLI.Command
  alias ClaudeCode.CLI.Control
  alias ClaudeCode.CLI.Input
  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Hook.Registry, as: HookRegistry
  alias ClaudeCode.MCP.Server, as: MCPServer
  alias ClaudeCode.MCP.Status, as: MCPStatus
  alias ClaudeCode.Model
  alias ClaudeCode.Session.AccountInfo
  alias ClaudeCode.Session.AgentInfo
  alias ClaudeCode.Session.SlashCommand

  require Logger

  @default_control_timeout 60_000

  # Keys consumed by Adapter.Port that should never reach CLI command building.
  @adapter_internal_keys [
    :callback_proxy,
    :control_timeout,
    :hook_registry,
    :sdk_mcp_servers,
    :max_buffer_size
  ]

  defstruct [
    :session,
    :session_options,
    :port,
    :buffer,
    :current_request,
    :api_key,
    :server_info,
    :hook_registry,
    :hooks_wire,
    :callback_proxy,
    :session_id,
    :cwd,
    status: :provisioning,
    control_counter: 0,
    control_timeout: @default_control_timeout,
    pending_control_requests: %{},
    max_buffer_size: 1_048_576,
    sdk_mcp_servers: %{}
  ]

  # ============================================================================
  # Client API (Adapter Behaviour)
  # ============================================================================

  @impl ClaudeCode.Adapter
  def start_link(session, opts) do
    GenServer.start_link(__MODULE__, {session, opts})
  end

  @impl ClaudeCode.Adapter
  def send_query(adapter, request_id, prompt, opts) do
    GenServer.call(adapter, {:query, request_id, prompt, opts}, :infinity)
  end

  @impl ClaudeCode.Adapter
  def health(adapter) do
    GenServer.call(adapter, :health)
  end

  @impl ClaudeCode.Adapter
  def stop(adapter) do
    GenServer.stop(adapter, :normal)
  end

  @impl ClaudeCode.Adapter
  def send_control_request(adapter, subtype, params) do
    GenServer.call(adapter, {:control_request, subtype, params}, :infinity)
  end

  @impl ClaudeCode.Adapter
  def get_server_info(adapter) do
    GenServer.call(adapter, :get_server_info)
  end

  @impl ClaudeCode.Adapter
  def interrupt(adapter) do
    GenServer.call(adapter, :interrupt)
  end

  @impl ClaudeCode.Adapter
  def execute(adapter, m, f, a) do
    GenServer.call(adapter, {:execute, m, f, a})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl GenServer
  def init({session, opts}) do
    hooks_map = Keyword.get(opts, :hooks)
    can_use_tool = Keyword.get(opts, :can_use_tool)
    {built_registry, hooks_wire} = HookRegistry.new(hooks_map, can_use_tool)

    # Callers may provide a pre-built hook registry (e.g. a partitioned subset).
    hook_registry =
      case Keyword.get(opts, :hook_registry) do
        %HookRegistry{} = reg -> reg
        nil -> built_registry
      end

    # Strip adapter-internal keys that should never reach CLI command building
    cli_opts = Keyword.drop(opts, @adapter_internal_keys)

    # Callers may provide a pre-built sdk_mcp_servers map (e.g. stub entries
    # when actual server modules aren't locally available).
    sdk_mcp_servers =
      case Keyword.get(opts, :sdk_mcp_servers) do
        pre when is_map(pre) and map_size(pre) > 0 -> pre
        _ -> extract_sdk_mcp_servers(opts)
      end

    state = %__MODULE__{
      session: session,
      session_options: cli_opts,
      buffer: "",
      api_key: Keyword.get(opts, :api_key),
      max_buffer_size: Keyword.get(opts, :max_buffer_size, 1_048_576),
      control_timeout: Keyword.get(opts, :control_timeout, @default_control_timeout),
      hook_registry: hook_registry,
      hooks_wire: hooks_wire,
      sdk_mcp_servers: sdk_mcp_servers,
      callback_proxy: Keyword.get(opts, :callback_proxy),
      cwd: Keyword.get(opts, :cwd) || File.cwd!()
    }

    Process.link(session)
    if state.callback_proxy, do: Process.monitor(state.callback_proxy)
    Adapter.notify_status(session, :provisioning)

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    # Resolve the CLI binary in a separate process so the GenServer stays
    # responsive during potentially slow auto-install (curl | bash).
    # Port opening must happen back in our process for ownership.
    adapter = self()
    session_options = state.session_options
    api_key = state.api_key

    Task.start_link(fn ->
      result = resolve_cli(session_options, api_key)
      send(adapter, {:cli_resolved, result})
    end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:query, request_id, prompt, opts}, _from, state) do
    session_id = Keyword.get(opts, :session_id) || "default"

    case ensure_connected(state) do
      {:ok, connected_state} ->
        message = Input.user_message(prompt, session_id)
        Port.command(connected_state.port, message <> "\n")
        {:reply, :ok, %{connected_state | current_request: request_id}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:health, _from, state) do
    health =
      case state do
        %{status: :provisioning} -> {:unhealthy, :provisioning}
        %{port: port} when not is_nil(port) -> if(Port.info(port), do: :healthy, else: {:unhealthy, :port_dead})
        _ -> {:unhealthy, :not_connected}
      end

    {:reply, health, state}
  end

  @impl GenServer
  def handle_call({:control_request, subtype, params}, from, state) do
    case state.port do
      nil ->
        {:reply, {:error, :not_connected}, state}

      port ->
        {request_id, new_counter} = next_request_id(state.control_counter)

        case build_control_json(subtype, request_id, params) do
          {:error, _} = error ->
            {:reply, error, state}

          json ->
            Port.command(port, json <> "\n")

            pending = Map.put(state.pending_control_requests, request_id, {subtype, from})
            schedule_control_timeout(state.control_timeout, request_id)

            {:noreply, %{state | control_counter: new_counter, pending_control_requests: pending}}
        end
    end
  end

  @impl GenServer
  def handle_call(:get_server_info, _from, state) do
    {:reply, {:ok, state.server_info}, state}
  end

  def handle_call(:interrupt, _from, %{port: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:interrupt, _from, state) do
    {request_id, new_counter} = next_request_id(state.control_counter)
    json = Control.interrupt_request(request_id)
    Port.command(state.port, json <> "\n")
    {:reply, :ok, %{state | control_counter: new_counter}}
  end

  def handle_call({:execute, m, f, a}, _from, state) do
    {:reply, apply(m, f, a), state}
  end

  @impl GenServer
  def handle_info({:cli_resolved, {:ok, {executable, args, streaming_opts}}}, state) do
    case open_cli_port(executable, args, state, streaming_opts) do
      {:ok, port} ->
        new_state = %{state | port: port, buffer: "", status: :initializing}
        send_initialize_handshake(new_state)

      {:error, reason} ->
        Adapter.notify_status(state.session, {:error, reason})
        {:noreply, %{state | status: :disconnected}}
    end
  end

  def handle_info({:cli_resolved, {:error, reason}}, state) do
    Adapter.notify_status(state.session, {:error, reason})
    {:noreply, %{state | status: :disconnected}}
  end

  def handle_info({port, {:data, data}}, %{port: port} = state) do
    new_buffer = state.buffer <> data
    {lines, remaining_buffer} = extract_lines(new_buffer)

    new_state =
      Enum.reduce(lines, %{state | buffer: remaining_buffer}, fn line, acc_state ->
        process_line(line, acc_state)
      end)

    if byte_size(new_state.buffer) > new_state.max_buffer_size do
      Logger.error(
        "Buffer overflow: incomplete line is #{byte_size(new_state.buffer)} bytes, exceeds max #{new_state.max_buffer_size}"
      )

      {:noreply, handle_port_disconnect(new_state, {:buffer_overflow, byte_size(new_state.buffer)})}
    else
      {:noreply, new_state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.debug("CLI exited with status #{status}")
    {:noreply, handle_port_disconnect(state, {:cli_exit, status})}
  end

  def handle_info({:DOWN, _ref, :port, port, reason}, %{port: port} = state) do
    Logger.error("CLI port closed: #{inspect(reason)}")
    {:noreply, handle_port_disconnect(state, {:port_closed, reason})}
  end

  def handle_info({port, :eof}, %{port: port} = state) do
    {:noreply, state}
  end

  def handle_info({:control_timeout, request_id}, state) do
    case Map.pop(state.pending_control_requests, request_id) do
      {nil, _} ->
        {:noreply, state}

      {{:initialize, session}, remaining} ->
        Adapter.notify_status(session, {:error, :initialize_timeout})
        {:noreply, %{state | pending_control_requests: remaining, status: :disconnected}}

      {{_subtype, from}, remaining} ->
        GenServer.reply(from, {:error, :control_timeout})
        {:noreply, %{state | pending_control_requests: remaining}}
    end
  end

  def handle_info({:DOWN, _ref, :process, proxy, reason}, %{callback_proxy: proxy} = state) when is_pid(proxy) do
    Logger.warning("Callback proxy down: #{inspect(reason)}")
    {:noreply, %{state | callback_proxy: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("CLI Adapter unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.port && Port.info(state.port) do
      # Send interrupt to stop any in-flight generation before closing the port.
      # Without this, the CLI keeps consuming API tokens until it notices
      # the broken pipe on its next stdout write.
      {request_id, _} = next_request_id(state.control_counter)
      json = Control.interrupt_request(request_id)
      Port.command(state.port, json <> "\n")
      Port.close(state.port)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  # ============================================================================
  # Private Functions - Port Management
  # ============================================================================

  defp handle_port_disconnect(state, error) do
    for {_req_id, pending} <- state.pending_control_requests do
      case pending do
        {:initialize, session} ->
          Adapter.notify_status(session, {:error, error})

        {_subtype, from} ->
          GenServer.reply(from, {:error, error})
      end
    end

    if state.current_request do
      Adapter.notify_error(state.session, state.current_request, error)
    end

    %{state | port: nil, current_request: nil, buffer: "", status: :disconnected, pending_control_requests: %{}}
  end

  defp send_initialize_handshake(state) do
    agents = Keyword.get(state.session_options, :agents)
    hooks_wire = state.hooks_wire

    sdk_mcp_server_names =
      case Map.keys(state.sdk_mcp_servers) do
        [] -> nil
        names -> names
      end

    extra_opts =
      []
      |> maybe_add_opt(state.session_options, :prompt_suggestions)
      |> maybe_add_opt(state.session_options, :tool_config)

    {request_id, new_counter} = next_request_id(state.control_counter)
    json = Control.initialize_request(request_id, hooks_wire, agents, sdk_mcp_server_names, extra_opts)
    Port.command(state.port, json <> "\n")

    pending = Map.put(state.pending_control_requests, request_id, {:initialize, state.session})
    schedule_control_timeout(state.control_timeout, request_id)

    {:noreply, %{state | control_counter: new_counter, pending_control_requests: pending}}
  end

  defp ensure_connected(%{status: :provisioning}), do: {:error, :provisioning}
  defp ensure_connected(%{status: :initializing}), do: {:error, :initializing}

  defp ensure_connected(%{port: nil, status: :disconnected} = state) do
    case spawn_cli(state) do
      {:ok, port} ->
        Adapter.notify_status(state.session, :ready)
        {:ok, %{state | port: port, buffer: "", status: :ready}}

      {:error, reason} ->
        Logger.error("Failed to reconnect to CLI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_connected(state), do: {:ok, state}

  # Resolves the CLI binary and builds the command. This may trigger auto-install
  # which can take seconds, so call from a Task during initial provisioning.
  defp resolve_cli(session_options, _api_key) do
    streaming_opts = Keyword.put(session_options, :input_format, :stream_json)
    resume_session_id = Keyword.get(session_options, :resume)

    case Resolver.find_binary(streaming_opts) do
      {:ok, executable} ->
        args = Command.build_args("", streaming_opts, resume_session_id)
        {:ok, {executable, List.delete_at(args, -1), streaming_opts}}

      {:error, :not_found} ->
        {:error, {:cli_not_found, Installer.cli_not_found_message()}}

      {:error, reason} ->
        {:error, {:cli_not_found, "CLI resolution failed: #{inspect(reason)}"}}
    end
  end

  # Synchronous spawn -- resolves binary and opens port in the same process.
  # Used by ensure_connected for reconnection (binary already installed, fast path).
  defp spawn_cli(state) do
    case resolve_cli(state.session_options, state.api_key) do
      {:ok, {executable, args, streaming_opts}} ->
        open_cli_port(executable, args, state, streaming_opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp open_cli_port(executable, args, state, opts) do
    exe_path = executable |> String.to_charlist() |> :os.find_executable()

    if !exe_path do
      raise "CLI executable not found: #{executable}"
    end

    env_list = prepare_env(state)

    port_opts = maybe_add_cd([{:args, args}, {:env, env_list}, :binary, :exit_status, :stderr_to_stdout], opts)

    port = Port.open({:spawn_executable, exe_path}, port_opts)

    {:ok, port}
  rescue
    e -> {:error, {:port_open_failed, e}}
  end

  defp maybe_add_cd(port_opts, opts) do
    case Keyword.get(opts, :cwd) do
      nil -> port_opts
      cwd_path -> [{:cd, String.to_charlist(cwd_path)} | port_opts]
    end
  end

  defp prepare_env(state) do
    state.session_options
    |> build_env(state.api_key)
    |> Enum.map(fn
      {key, false} -> {String.to_charlist(key), false}
      {key, value} -> {String.to_charlist(key), String.to_charlist(to_string(value))}
    end)
  end

  # ============================================================================
  # Testable Functions (public but not part of API)
  # ============================================================================

  @doc false
  def sdk_env_vars do
    %{
      "CLAUDE_CODE_ENTRYPOINT" => "sdk-ex",
      "CLAUDE_AGENT_SDK_VERSION" => ClaudeCode.version()
    }
  end

  @doc false
  def filter_system_env(sys_env, inherit_env, opts \\ [])

  def filter_system_env(sys_env, :all, _opts) do
    Map.delete(sys_env, "CLAUDECODE")
  end

  def filter_system_env(sys_env, inherit_list, opts) when is_list(inherit_list) do
    if opts[:debug], do: log_unmatched_entries(inherit_list, sys_env)

    Map.filter(sys_env, fn {key, _value} ->
      matches_inherit_list?(key, inherit_list)
    end)
  end

  defp matches_inherit_list?(key, inherit_list) do
    Enum.any?(inherit_list, fn
      {:prefix, prefix} -> String.starts_with?(key, prefix)
      exact when is_binary(exact) -> key == exact
    end)
  end

  defp log_unmatched_entries(inherit_list, sys_env) do
    Enum.each(inherit_list, fn
      {:prefix, prefix} ->
        if !Enum.any?(sys_env, fn {key, _} -> String.starts_with?(key, prefix) end) do
          Logger.debug("inherit_env: {:prefix, #{inspect(prefix)}} — no matching system env vars")
        end

      exact when is_binary(exact) ->
        if !Map.has_key?(sys_env, exact) do
          Logger.debug("inherit_env: #{inspect(exact)} — no matching system env var")
        end
    end)
  end

  @doc false
  def build_env(session_options, api_key) do
    inherit_env = Keyword.get(session_options, :inherit_env, :all)
    user_env = Keyword.get(session_options, :env, %{})
    debug = Keyword.get(session_options, :debug, false)

    System.get_env()
    |> filter_system_env(inherit_env, debug: !!debug)
    |> Map.merge(sdk_env_vars())
    |> Map.merge(user_env)
    |> maybe_put_api_key(api_key)
    |> maybe_put_file_checkpointing(session_options)
  end

  defp maybe_put_api_key(env, api_key) when is_binary(api_key) do
    Map.put(env, "ANTHROPIC_API_KEY", api_key)
  end

  defp maybe_put_api_key(env, _), do: env

  defp maybe_put_file_checkpointing(env, opts) do
    if Keyword.get(opts, :enable_file_checkpointing, false) do
      Map.put(env, "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING", "true")
    else
      env
    end
  end

  @doc false
  def extract_lines(buffer) do
    case String.split(buffer, "\n") do
      [incomplete] -> {[], incomplete}
      lines -> {List.delete_at(lines, -1), List.last(lines)}
    end
  end

  # ============================================================================
  # Private Functions - Message Processing
  # ============================================================================

  defp process_line("", state), do: state

  defp process_line(line, state) do
    case Jason.decode(line) do
      {:ok, json} ->
        case Control.classify(json) do
          {:control_response, msg} ->
            handle_control_response(msg, state)

          {:control_request, msg} ->
            handle_inbound_control_request(msg, state)

          {:control_cancel, msg} ->
            handle_control_cancel(msg, state)

          {:message, json_msg} ->
            handle_sdk_message(json_msg, state)
        end

      {:error, _} ->
        Logger.debug("Non-JSON CLI output: #{String.slice(line, 0, 500)}")
        state
    end
  end

  defp handle_sdk_message(json, %{current_request: nil} = state) do
    maybe_capture_session_id(json, state)
  end

  defp handle_sdk_message(json, state) do
    Adapter.notify_message(state.session, state.current_request, json)

    state = maybe_capture_session_id(json, state)

    if json["type"] == "result" do
      %{state | current_request: nil}
    else
      state
    end
  end

  defp maybe_capture_session_id(%{"type" => "system", "session_id" => sid}, %{session_id: current} = state)
       when is_binary(sid) and sid != current do
    %{state | session_id: sid}
  end

  defp maybe_capture_session_id(_, state), do: state

  defp handle_control_response(msg, state) do
    {request_id, result} =
      case Control.parse_control_response(msg) do
        {:ok, id, response} -> {id, {:ok, Parser.normalize_keys(response)}}
        {:error, id, error_msg} -> {id, {:error, error_msg}}
      end

    case Map.pop(state.pending_control_requests, request_id) do
      {nil, _} ->
        Logger.warning("Received control response for unknown request: #{request_id}")
        state

      {{:initialize, session}, remaining} ->
        complete_initialize(result, session, %{state | pending_control_requests: remaining})

      {{subtype, from}, remaining} ->
        reply = with {:ok, response} <- result, do: {:ok, parse_control_result(subtype, response)}
        GenServer.reply(from, reply)
        %{state | pending_control_requests: remaining}
    end
  end

  defp complete_initialize({:ok, response}, session, state) do
    Adapter.notify_status(session, :ready)
    %{state | server_info: parse_initialize_response(response), status: :ready}
  end

  defp complete_initialize({:error, error_msg}, session, state) do
    Adapter.notify_status(session, {:error, {:initialize_failed, error_msg}})
    %{state | status: :disconnected}
  end

  defp handle_control_cancel(%{"request_id" => cancel_id}, state) do
    Logger.debug("Received control cancel for request: #{cancel_id}")

    case Map.pop(state.pending_control_requests, cancel_id) do
      {nil, _} ->
        state

      {{:initialize, session}, remaining} ->
        Adapter.notify_status(session, {:error, :cancelled})
        %{state | pending_control_requests: remaining}

      {{_subtype, from}, remaining} ->
        GenServer.reply(from, {:error, :cancelled})
        %{state | pending_control_requests: remaining}
    end
  end

  defp handle_inbound_control_request(msg, state) do
    request_id = get_in(msg, ["request_id"])
    request = get_in(msg, ["request"])
    subtype = get_in(request, ["subtype"])

    result = dispatch_control_request(subtype, request, msg, state)

    send_control_result(request_id, result, state)
  end

  defp dispatch_control_request("hook_callback", request, msg, state) do
    route_hook_callback(request, state.hook_registry, msg, state)
  end

  defp dispatch_control_request("mcp_message", _request, msg, state) do
    route_mcp_message(msg, state)
  end

  defp dispatch_control_request("can_use_tool", request, msg, state) do
    route_can_use_tool(request, msg, state)
  end

  defp dispatch_control_request("elicitation", request, _msg, _state) do
    Logger.info("Received MCP elicitation request (not yet implemented): #{inspect(request)}")
    {:error, "Not implemented: elicitation"}
  end

  defp dispatch_control_request(subtype, _request, _msg, _state) do
    Logger.warning("Received unhandled control request: #{subtype}")
    {:error, "Not implemented: #{subtype}"}
  end

  defp send_control_result(request_id, result, state) do
    response =
      case result do
        {:ok, data} -> Control.success_response(request_id, data)
        {:error, reason} -> Control.error_response(request_id, reason)
      end

    if state.port, do: Port.command(state.port, response <> "\n")
    state
  end

  defp route_mcp_message(msg, %{callback_proxy: proxy, control_timeout: timeout}) when is_pid(proxy) do
    proxy_call(proxy, msg, timeout)
  end

  defp route_mcp_message(msg, state) do
    request = get_in(msg, ["request"])
    server_name = request["server_name"]
    jsonrpc = request["message"]
    {:ok, ControlHandler.handle_mcp_message(server_name, jsonrpc, state.sdk_mcp_servers)}
  end

  # Handle locally when callback exists in local registry, otherwise proxy
  defp route_can_use_tool(request, _msg, %{hook_registry: %HookRegistry{can_use_tool: cb} = registry} = state)
       when cb != nil do
    {:ok, ControlHandler.handle_can_use_tool(request, registry, session_context(state))}
  end

  defp route_can_use_tool(_request, msg, %{callback_proxy: proxy, control_timeout: timeout}) when is_pid(proxy) do
    proxy_call(proxy, msg, timeout)
  end

  # No local callback and no proxy — ControlHandler will default to "allow"
  defp route_can_use_tool(request, _msg, state) do
    {:ok, ControlHandler.handle_can_use_tool(request, state.hook_registry, session_context(state))}
  end

  defp session_context(state) do
    %{cwd: state.cwd, session_id: state.session_id}
  end

  # Check local registry first (remote hooks), then fall back to proxy (local hooks)
  defp route_hook_callback(request, hook_registry, msg, state) do
    case HookRegistry.lookup(hook_registry, request["callback_id"]) do
      {:ok, _} ->
        ControlHandler.handle_hook_callback(request, hook_registry)

      :error ->
        case state do
          %{callback_proxy: proxy, control_timeout: timeout} when is_pid(proxy) ->
            proxy_call(proxy, msg, timeout)

          _ ->
            ControlHandler.handle_hook_callback(request, hook_registry)
        end
    end
  end

  defp proxy_call(proxy, msg, timeout) do
    GenServer.call(proxy, {:control_request, msg}, timeout)
  catch
    :exit, _ ->
      Logger.warning("Callback proxy unavailable")
      {:error, "Callback proxy unavailable"}
  end

  @doc false
  def extract_sdk_mcp_servers(opts) do
    opts
    |> Keyword.get(:mcp_servers)
    |> Kernel.||(%{})
    |> Enum.flat_map(fn
      {name, module} when is_atom(module) ->
        if MCPServer.sdk_server?(module), do: [{name, {module, %{}}}], else: []

      {name, %{module: module} = config} when is_atom(module) ->
        if MCPServer.sdk_server?(module), do: [{name, {module, Map.get(config, :assigns, %{})}}], else: []

      _ ->
        []
    end)
    |> Map.new()
  end

  @doc false
  def handle_mcp_message(server_name, jsonrpc, sdk_mcp_servers) do
    %{"mcp_response" => response} = ControlHandler.handle_mcp_message(server_name, jsonrpc, sdk_mcp_servers)
    response
  end

  defp next_request_id(counter) do
    {Control.generate_request_id(counter), counter + 1}
  end

  defp maybe_add_opt(acc, opts, key) do
    case Keyword.get(opts, key) do
      nil -> acc
      value -> Keyword.put(acc, key, value)
    end
  end

  defp parse_control_result(:mcp_status, %{"mcp_servers" => servers}) when is_list(servers) do
    Enum.map(servers, &MCPStatus.new/1)
  end

  defp parse_control_result(:set_mcp_servers, response) when is_map(response) do
    %{
      added: response["added"] || [],
      removed: response["removed"] || [],
      errors: response["errors"] || %{}
    }
  end

  defp parse_control_result(:rewind_files, response) when is_map(response) do
    %{
      can_rewind: response["can_rewind"],
      error: response["error"],
      files_changed: response["files_changed"],
      insertions: response["insertions"],
      deletions: response["deletions"]
    }
  end

  defp parse_control_result(_subtype, response), do: response

  @spec parse_initialize_response(map()) :: ClaudeCode.CLI.Control.Types.initialize_response()
  defp parse_initialize_response(response) when is_map(response) do
    %{
      commands: parse_list(response["commands"], &SlashCommand.new/1),
      agents: parse_list(response["agents"], &AgentInfo.new/1),
      models: parse_list(response["models"], &Model.Info.new/1),
      account: parse_optional(response["account"], &AccountInfo.new/1),
      output_style: response["output_style"],
      available_output_styles: response["available_output_styles"] || [],
      fast_mode_state: response["fast_mode_state"]
    }
  end

  defp parse_list(nil, _parser), do: []
  defp parse_list(list, parser) when is_list(list), do: Enum.map(list, parser)

  defp parse_optional(nil, _parser), do: nil
  defp parse_optional(map, parser) when is_map(map), do: parser.(map)

  defp build_control_json(:initialize, request_id, params) do
    hooks = Map.get(params, :hooks)
    agents = Map.get(params, :agents)
    sdk_mcp_servers = Map.get(params, :sdk_mcp_servers)
    extra_opts = Map.get(params, :extra_opts, [])
    Control.initialize_request(request_id, hooks, agents, sdk_mcp_servers, extra_opts)
  end

  defp build_control_json(:set_model, request_id, %{model: model}) do
    Control.set_model_request(request_id, model)
  end

  defp build_control_json(:set_permission_mode, request_id, %{mode: mode}) do
    Control.set_permission_mode_request(request_id, to_string(mode))
  end

  defp build_control_json(:rewind_files, request_id, %{user_message_id: id} = params) do
    opts = if params[:dry_run], do: [dry_run: true], else: []
    Control.rewind_files_request(request_id, id, opts)
  end

  defp build_control_json(:mcp_status, request_id, _params) do
    Control.mcp_status_request(request_id)
  end

  defp build_control_json(:mcp_reconnect, request_id, %{server_name: name}) do
    Control.mcp_reconnect_request(request_id, name)
  end

  defp build_control_json(:mcp_toggle, request_id, %{server_name: name, enabled: enabled}) do
    Control.mcp_toggle_request(request_id, name, enabled)
  end

  defp build_control_json(:set_mcp_servers, request_id, %{servers: servers}) do
    Control.mcp_set_servers_request(request_id, servers)
  end

  defp build_control_json(:stop_task, request_id, %{task_id: task_id}) do
    Control.stop_task_request(request_id, task_id)
  end

  defp build_control_json(subtype, _request_id, _params) do
    {:error, {:unknown_control_subtype, subtype}}
  end

  defp schedule_control_timeout(timeout, request_id) do
    Process.send_after(self(), {:control_timeout, request_id}, timeout)
  end
end
