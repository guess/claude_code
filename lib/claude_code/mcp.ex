defmodule ClaudeCode.MCP do
  @moduledoc """
  Optional integration with Hermes MCP (Model Context Protocol).

  This module provides helpers for exposing Elixir tools to Claude via the MCP protocol.
  It requires the optional `hermes_mcp` dependency to be installed.

  ## Overview

  MCP (Model Context Protocol) allows Claude to interact with external tools and services.
  With this integration, you can:

  1. Define tools using Hermes MCP patterns
  2. Start an MCP server (HTTP or stdio transport)
  3. Generate config files for the Claude CLI
  4. Connect ClaudeCode sessions to your MCP servers

  ## Installation

  Add `hermes_mcp` to your dependencies in `mix.exs`:

      defp deps do
        [
          {:claude_code, "~> 0.4"},
          {:hermes_mcp, "~> 0.14"}  # Required for MCP integration
        ]
      end

  ## Usage Example

  ### 1. Define your tools using Hermes

      defmodule MyApp.Calculator do
        use Hermes.Server.Component, type: :tool

        @impl true
        def definition do
          %{
            name: "add",
            description: "Add two numbers together",
            inputSchema: %{
              type: "object",
              properties: %{
                a: %{type: "number", description: "First number"},
                b: %{type: "number", description: "Second number"}
              },
              required: ["a", "b"]
            }
          }
        end

        @impl true
        def execute(%{"a" => a, "b" => b}, _frame) do
          {:ok, [%{type: "text", text: "\#{a + b}"}]}
        end
      end

      defmodule MyApp.MCPServer do
        use Hermes.Server,
          name: "my-tools",
          version: "1.0.0"

        tool MyApp.Calculator
      end

  ### 2. Start the MCP server and connect to ClaudeCode

      # Start MCP server
      {:ok, config_path} = ClaudeCode.MCP.Server.start_link(MyApp.MCPServer, port: 9001)

      # Connect ClaudeCode session with the MCP server
      {:ok, session} = ClaudeCode.start_link(
        mcp_config: config_path
      )

      # Claude can now use your tools!
      {:ok, response} = ClaudeCode.query(session, "What is 5 + 3?")

  ## Architecture

  ```
  ┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────┐
  │   ClaudeCode        │────▶│   Claude CLI     │────▶│  Hermes MCP     │
  │   Session           │     │   (subprocess)   │     │  Server         │
  └─────────────────────┘     └──────────────────┘     └─────────────────┘
                                      │                        │
                                      │  MCP Protocol          │
                                      │  (HTTP/SSE or stdio)   │
                                      └────────────────────────┘
  ```

  ## Submodules

  - `ClaudeCode.MCP.Config` - Generate MCP configuration files
  - `ClaudeCode.MCP.Server` - Start and manage Hermes MCP servers
  """

  @doc """
  Checks if Hermes MCP is available.

  Returns `true` if the `hermes_mcp` dependency is installed and loaded.

  ## Example

      if ClaudeCode.MCP.available?() do
        # Use MCP features
      else
        # Fall back or show error
      end
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Hermes.Server)
  end

  @doc """
  Raises an error if Hermes MCP is not available.

  Use this at the start of functions that require Hermes to provide
  a clear error message.

  ## Example

      def start_mcp_server(module, opts) do
        ClaudeCode.MCP.require_hermes!()
        # ... rest of implementation
      end
  """
  @spec require_hermes!() :: :ok | no_return()
  def require_hermes! do
    if available?() do
      :ok
    else
      raise """
      Hermes MCP is required but not available.

      Add hermes_mcp to your dependencies in mix.exs:

          defp deps do
            [
              {:hermes_mcp, "~> 0.14"}
            ]
          end

      Then run: mix deps.get
      """
    end
  end
end
