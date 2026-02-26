defmodule ClaudeCode.MCP do
  @moduledoc """
  Optional integration with Hermes MCP (Model Context Protocol).

  This module provides runtime checks for the optional `hermes_mcp` dependency,
  which is required for defining custom tools via `ClaudeCode.MCP.Server`.

  ## Installation

  Add `hermes_mcp` to your dependencies in `mix.exs`:

      defp deps do
        [
          {:claude_code, "~> 0.25"},
          {:hermes_mcp, "~> 0.14"}  # Required for custom tools
        ]
      end

  ## Usage

  Define tools with `ClaudeCode.MCP.Server` and pass them via `:mcp_servers`:

      defmodule MyApp.Tools do
        use ClaudeCode.MCP.Server, name: "my-tools"

        tool :add, "Add two numbers" do
          field :x, :integer, required: true
          field :y, :integer, required: true
          def execute(%{x: x, y: y}), do: {:ok, "\#{x + y}"}
        end
      end

      {:ok, result} = ClaudeCode.query("What is 5 + 3?",
        mcp_servers: %{"my-tools" => MyApp.Tools},
        allowed_tools: ["mcp__my-tools__add"]
      )

  See the [Custom Tools](docs/guides/custom-tools.md) guide for details.
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
