defmodule ClaudeCode.MCP do
  @moduledoc """
  Integration with the Model Context Protocol (MCP).

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

  alias ClaudeCode.MCP.Backend
  alias ClaudeCode.MCP.Server

  @doc """
  Determines which backend handles the given MCP module.

  Returns:
  - `:sdk` — in-process SDK server (handled via Router, no subprocess)
  - `{:subprocess, backend_module}` — subprocess server, with the backend that can expand it
  - `:unknown` — unrecognized module
  """
  @spec backend_for(module()) :: :sdk | {:subprocess, module()} | :unknown
  def backend_for(module) when is_atom(module) do
    cond do
      Server.sdk_server?(module) -> :sdk
      Backend.Anubis.compatible?(module) -> {:subprocess, Backend.Anubis}
      Backend.Hermes.compatible?(module) -> {:subprocess, Backend.Hermes}
      true -> :unknown
    end
  end
end
