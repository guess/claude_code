defmodule ClaudeCode.MCP.Backend do
  @moduledoc false

  @doc "Returns a list of tool definition maps for the given server module."
  @callback list_tools(server_module :: module()) :: [map()]

  @doc "Calls a tool by name with the given params and assigns. Returns a JSONRPC-ready result map."
  @callback call_tool(
              server_module :: module(),
              tool_name :: String.t(),
              params :: map(),
              assigns :: map()
            ) :: {:ok, map()} | {:error, String.t()} | {:validation_error, String.t()}

  @doc "Returns server info map (name, version) for the initialize response."
  @callback server_info(server_module :: module()) :: map()

  @doc "Returns true if the given module is compatible with this backend (for subprocess detection)."
  @callback compatible?(module :: module()) :: boolean()

  # Dispatch to configured implementation

  def server_info(server_module), do: impl().server_info(server_module)
  def list_tools(server_module), do: impl().list_tools(server_module)

  def call_tool(server_module, tool_name, params, assigns),
    do: impl().call_tool(server_module, tool_name, params, assigns)

  defp impl do
    Application.get_env(:claude_code, __MODULE__) || default_impl()
  end

  defp default_impl do
    cond do
      Code.ensure_loaded?(ClaudeCode.MCP.Backend.Anubis) -> ClaudeCode.MCP.Backend.Anubis
      Code.ensure_loaded?(ClaudeCode.MCP.Backend.Hermes) -> ClaudeCode.MCP.Backend.Hermes
      true -> raise "No MCP backend available. Add :anubis_mcp or :hermes_mcp to your deps."
    end
  end
end
