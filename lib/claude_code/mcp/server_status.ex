defmodule ClaudeCode.MCP.ServerStatus do
  @moduledoc """
  Status information for an MCP server connection.

  Returned by `ClaudeCode.Session.mcp_status/1`.

  ## Fields

    * `:name` - Server name as configured
    * `:status` - Current connection status (`:connected`, `:failed`, `:needs_auth`, `:pending`, `:disabled`)
    * `:server_info` - Server info map with `name` and `version` (available when connected)
    * `:error` - Error message (available when status is `:failed`)
    * `:config` - Server configuration map
    * `:scope` - Configuration scope (e.g., `"project"`, `"user"`, `"local"`)
    * `:tools` - List of tool maps with `name`, `description`, and `annotations` (available when connected)
  """

  use ClaudeCode.JSONEncoder

  defstruct [
    :name,
    :status,
    :server_info,
    :error,
    :config,
    :scope,
    :tools
  ]

  @type status :: :connected | :failed | :needs_auth | :pending | :disabled

  @type t :: %__MODULE__{
          name: String.t(),
          status: status(),
          server_info: %{name: String.t(), version: String.t()} | nil,
          error: String.t() | nil,
          config: map() | nil,
          scope: String.t() | nil,
          tools: [map()] | nil
        }

  @doc """
  Creates a ServerStatus from a JSON map.

  ## Examples

      iex> ClaudeCode.MCP.ServerStatus.new(%{"name" => "my-server", "status" => "connected"})
      %ClaudeCode.MCP.ServerStatus{name: "my-server", status: :connected}

  """
  @spec new(map()) :: t()
  def new(data) when is_map(data) do
    %__MODULE__{
      name: data["name"],
      status: parse_status(data["status"]),
      server_info: parse_server_info(data["server_info"]),
      error: data["error"],
      config: data["config"],
      scope: data["scope"],
      tools: data["tools"]
    }
  end

  defp parse_status("connected"), do: :connected
  defp parse_status("failed"), do: :failed
  defp parse_status("needs-auth"), do: :needs_auth
  defp parse_status("pending"), do: :pending
  defp parse_status("disabled"), do: :disabled
  defp parse_status(_), do: :pending

  defp parse_server_info(%{"name" => name, "version" => version}) do
    %{name: name, version: version}
  end

  defp parse_server_info(_), do: nil
end
