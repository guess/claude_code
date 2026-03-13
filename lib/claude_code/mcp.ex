defmodule ClaudeCode.MCP do
  @moduledoc """
  Integration with Hermes MCP (Model Context Protocol).

  This module provides the MCP integration layer. Custom tools are defined
  with `ClaudeCode.MCP.Server` and passed via `:mcp_servers`.

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
end
