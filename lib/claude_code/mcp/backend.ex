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
end
