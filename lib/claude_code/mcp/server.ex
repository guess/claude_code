defmodule ClaudeCode.MCP.Server do
  @moduledoc """
  Helper for starting and managing Hermes MCP servers for use with ClaudeCode.

  This module provides convenience functions to start Hermes MCP servers
  and automatically generate the configuration files needed by the Claude CLI.

  ## Prerequisites

  This module requires the `hermes_mcp` dependency:

      {:hermes_mcp, "~> 0.14"}

  ## Usage

  ### Starting an HTTP Server

      # Define your Hermes server module
      defmodule MyApp.MCPServer do
        use Hermes.Server,
          name: "my-tools",
          version: "1.0.0"

        tool MyApp.Calculator
        tool MyApp.FileReader
      end

      # Start the server and get config path
      {:ok, config_path} = ClaudeCode.MCP.Server.start_link(MyApp.MCPServer, port: 9001)

      # Use with ClaudeCode
      {:ok, session} = ClaudeCode.start_link(mcp_config: config_path)

  ### With Supervision

      # In your application supervisor
      children = [
        {ClaudeCode.MCP.Server, server: MyApp.MCPServer, port: 9001, name: :my_mcp}
      ]

  ## Architecture

  When started, this module:

  1. Validates that Hermes MCP is available
  2. Starts the Hermes server with HTTP transport
  3. Generates an MCP config file pointing to the server
  4. Returns the config file path for use with ClaudeCode
  """

  use GenServer

  alias ClaudeCode.MCP
  alias ClaudeCode.MCP.Config

  @type start_option ::
          {:server, module()}
          | {:port, pos_integer()}
          | {:host, String.t()}
          | {:name, GenServer.name()}
          | {:hermes_opts, keyword()}

  @doc """
  Starts an MCP server as a linked process.

  ## Options

  - `:server` - The Hermes server module (required)
  - `:port` - Port for HTTP transport (required)
  - `:host` - Hostname to bind (default: "localhost")
  - `:name` - GenServer name for this process (optional)
  - `:hermes_opts` - Additional options passed to Hermes.Server.start_link/1

  ## Returns

  - `{:ok, config_path}` - Path to the generated MCP config file
  - `{:error, reason}` - If startup fails

  ## Example

      {:ok, config_path} = ClaudeCode.MCP.Server.start_link(
        server: MyApp.MCPServer,
        port: 9001
      )
  """
  @spec start_link([start_option()]) :: {:ok, String.t()} | {:error, term()}
  def start_link(opts) when is_list(opts) do
    MCP.require_hermes!()

    server = Keyword.fetch!(opts, :server)
    port = Keyword.fetch!(opts, :port)
    host = Keyword.get(opts, :host, "localhost")
    name = Keyword.get(opts, :name)
    hermes_opts = Keyword.get(opts, :hermes_opts, [])

    gen_opts = if name, do: [name: name], else: []
    init_arg = {server, port, host, hermes_opts}

    case GenServer.start_link(__MODULE__, init_arg, gen_opts) do
      {:ok, pid} ->
        config_path = GenServer.call(pid, :get_config_path)
        {:ok, config_path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the config path from a running MCP server.

  ## Example

      config_path = ClaudeCode.MCP.Server.get_config_path(:my_mcp)
  """
  @spec get_config_path(GenServer.server()) :: String.t()
  def get_config_path(server) do
    GenServer.call(server, :get_config_path)
  end

  @doc """
  Generates a stdio command configuration for a Hermes server.

  This creates the command and args needed to start a Hermes server
  as a subprocess using stdio transport.

  ## Options

  - `:module` - The Hermes server module (required)
  - `:mix_env` - Mix environment (default: "prod")

  ## Example

      config = ClaudeCode.MCP.Server.stdio_command(
        module: MyApp.MCPServer
      )
      # => %{command: "mix", args: ["run", "--no-halt", "-e", "..."]}
  """
  @spec stdio_command(keyword()) :: %{command: String.t(), args: [String.t()], env: %{String.t() => String.t()}}
  def stdio_command(opts) do
    module = Keyword.fetch!(opts, :module)
    mix_env = Keyword.get(opts, :mix_env, "prod")

    startup_code = "#{inspect(module)}.start_link(transport: :stdio)"

    %{
      command: "mix",
      args: ["run", "--no-halt", "-e", startup_code],
      env: %{"MIX_ENV" => mix_env}
    }
  end

  # GenServer callbacks

  @impl true
  def init({server_module, port, host, hermes_opts}) do
    # Start the Hermes server with HTTP transport
    transport_opts = [
      transport: :http,
      http: [port: port, host: host]
    ]

    all_opts = Keyword.merge(hermes_opts, transport_opts)

    case start_hermes_server(server_module, all_opts) do
      {:ok, hermes_pid} ->
        # Generate config file
        server_name = get_server_name(server_module)
        config = Config.http_config(server_name, port: port, host: host)

        case Config.write_temp_config(config) do
          {:ok, config_path} ->
            state = %{
              hermes_pid: hermes_pid,
              config_path: config_path,
              port: port,
              host: host,
              server_module: server_module
            }

            {:ok, state}

          {:error, reason} ->
            {:stop, {:config_error, reason}}
        end

      {:error, reason} ->
        {:stop, {:hermes_error, reason}}
    end
  end

  @impl true
  def handle_call(:get_config_path, _from, state) do
    {:reply, state.config_path, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up config file
    if state.config_path && File.exists?(state.config_path) do
      File.rm(state.config_path)
    end

    :ok
  end

  # Private helpers

  # Hermes.Server.start_link expects the server module to implement
  # the Hermes.Server behaviour
  defp start_hermes_server(server_module, opts) do
    server_module.start_link(opts)
  rescue
    e -> {:error, {:start_failed, e}}
  end

  defp get_server_name(module) do
    # Try to get the name from the module, or derive from module name
    if function_exported?(module, :server_info, 0) do
      info = module.server_info()
      Map.get(info, :name, module_to_name(module))
    else
      module_to_name(module)
    end
  end

  defp module_to_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", "-")
  end
end
