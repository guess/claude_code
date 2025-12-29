defmodule ClaudeCode.MCP.Config do
  @moduledoc """
  Generates MCP configuration files for the Claude CLI.

  The Claude CLI expects MCP server configurations in a specific JSON format.
  This module provides helpers to generate these configuration files for
  different transport types (HTTP/SSE and stdio).

  ## Configuration Format

  The Claude CLI expects a JSON file with the following structure:

      {
        "mcpServers": {
          "server-name": {
            "command": "path/to/executable",
            "args": ["arg1", "arg2"],
            "env": {"KEY": "value"}
          }
        }
      }

  For HTTP/SSE transport:

      {
        "mcpServers": {
          "server-name": {
            "url": "http://localhost:9001/sse"
          }
        }
      }

  ## Usage

      # Generate HTTP config
      config = ClaudeCode.MCP.Config.http_config("my-server", port: 9001)

      # Generate stdio config
      config = ClaudeCode.MCP.Config.stdio_config("my-server",
        command: "elixir",
        args: ["-S", "mix", "run", "--no-halt", "-e", "MyApp.MCPServer.start_link()"]
      )

      # Write to temp file for Claude CLI
      {:ok, path} = ClaudeCode.MCP.Config.write_temp_config(config)

      # Use with ClaudeCode session
      {:ok, session} = ClaudeCode.start_link(mcp_config: path)
  """

  @type server_config :: %{
          optional(:command) => String.t(),
          optional(:args) => [String.t()],
          optional(:env) => %{String.t() => String.t()},
          optional(:url) => String.t()
        }

  @type mcp_config :: %{
          mcpServers: %{String.t() => server_config()}
        }

  @doc """
  Generates an HTTP/SSE transport configuration for an MCP server.

  ## Options

  - `:port` - Port number (required)
  - `:host` - Hostname (default: "localhost")
  - `:path` - SSE endpoint path (default: "/sse")
  - `:scheme` - URL scheme (default: "http")

  ## Example

      config = ClaudeCode.MCP.Config.http_config("calculator", port: 9001)
      # => %{mcpServers: %{"calculator" => %{url: "http://localhost:9001/sse"}}}

      config = ClaudeCode.MCP.Config.http_config("secure-server",
        port: 443,
        host: "api.example.com",
        scheme: "https",
        path: "/mcp/sse"
      )
  """
  @spec http_config(String.t(), keyword()) :: mcp_config()
  def http_config(name, opts) when is_binary(name) and is_list(opts) do
    port = Keyword.fetch!(opts, :port)
    host = Keyword.get(opts, :host, "localhost")
    path = Keyword.get(opts, :path, "/sse")
    scheme = Keyword.get(opts, :scheme, "http")

    url = "#{scheme}://#{host}:#{port}#{path}"

    %{
      mcpServers: %{
        name => %{url: url}
      }
    }
  end

  @doc """
  Generates a stdio transport configuration for an MCP server.

  ## Options

  - `:command` - Executable command (required)
  - `:args` - List of command arguments (default: [])
  - `:env` - Environment variables map (default: %{})

  ## Example

      config = ClaudeCode.MCP.Config.stdio_config("my-tools",
        command: "elixir",
        args: ["-S", "mix", "run", "--no-halt", "-e", "MyApp.start_mcp()"]
      )

      config = ClaudeCode.MCP.Config.stdio_config("node-server",
        command: "npx",
        args: ["@example/mcp-server"],
        env: %{"API_KEY" => "secret"}
      )
  """
  @spec stdio_config(String.t(), keyword()) :: mcp_config()
  def stdio_config(name, opts) when is_binary(name) and is_list(opts) do
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, %{})

    server_config = maybe_add_env(%{command: command, args: args}, env)

    %{
      mcpServers: %{
        name => server_config
      }
    }
  end

  @doc """
  Merges multiple MCP configurations into a single configuration.

  This is useful when you have multiple MCP servers that should all
  be available to Claude.

  ## Example

      calculator = ClaudeCode.MCP.Config.http_config("calculator", port: 9001)
      database = ClaudeCode.MCP.Config.http_config("database", port: 9002)

      merged = ClaudeCode.MCP.Config.merge_configs([calculator, database])
      # => %{mcpServers: %{"calculator" => ..., "database" => ...}}
  """
  @spec merge_configs([mcp_config()]) :: mcp_config()
  def merge_configs(configs) when is_list(configs) do
    merged_servers =
      Enum.reduce(configs, %{}, fn config, acc ->
        Map.merge(acc, config.mcpServers)
      end)

    %{mcpServers: merged_servers}
  end

  @doc """
  Writes an MCP configuration to a temporary file.

  Returns the path to the temporary file, which can be passed to
  ClaudeCode via the `:mcp_config` option.

  The temporary file is created in the system's temp directory and
  will be automatically cleaned up by the OS eventually.

  ## Options

  - `:prefix` - Filename prefix (default: "claude_mcp_config")
  - `:dir` - Directory for temp file (default: System.tmp_dir!())

  ## Example

      config = ClaudeCode.MCP.Config.http_config("my-server", port: 9001)
      {:ok, path} = ClaudeCode.MCP.Config.write_temp_config(config)

      {:ok, session} = ClaudeCode.start_link(mcp_config: path)
  """
  @spec write_temp_config(mcp_config(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def write_temp_config(config, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "claude_mcp_config")
    dir = Keyword.get(opts, :dir, System.tmp_dir!())

    filename = "#{prefix}_#{:erlang.unique_integer([:positive])}.json"
    path = Path.join(dir, filename)

    case Jason.encode(config, pretty: true) do
      {:ok, json} ->
        case File.write(path, json) do
          :ok -> {:ok, path}
          {:error, reason} -> {:error, {:write_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:encode_failed, reason}}
    end
  end

  @doc """
  Converts an MCP configuration to a JSON string.

  ## Options

  - `:pretty` - Format with indentation (default: false)

  ## Example

      config = ClaudeCode.MCP.Config.http_config("my-server", port: 9001)
      {:ok, json} = ClaudeCode.MCP.Config.to_json(config, pretty: true)
  """
  @spec to_json(mcp_config(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_json(config, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, false)

    if pretty do
      Jason.encode(config, pretty: true)
    else
      Jason.encode(config)
    end
  end

  # Private helpers

  defp maybe_add_env(config, env) when map_size(env) == 0, do: config
  defp maybe_add_env(config, env), do: Map.put(config, :env, env)
end
