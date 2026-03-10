defmodule ClaudeCode.Content.MCPToolUseBlock do
  @moduledoc """
  Represents an MCP tool use content block within a Claude message.

  MCP tool use blocks indicate that Claude wants to invoke a tool
  provided by an MCP (Model Context Protocol) server.
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :id, :name, :server_name, :input]
  defstruct [:type, :id, :name, :server_name, :input]

  @type t :: %__MODULE__{
          type: :mcp_tool_use,
          id: String.t(),
          name: String.t(),
          server_name: String.t(),
          input: any()
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "mcp_tool_use"} = data) do
    required = ["id", "name", "server_name", "input"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      {:ok,
       %__MODULE__{
         type: :mcp_tool_use,
         id: data["id"],
         name: data["name"],
         server_name: data["server_name"],
         input: data["input"]
       }}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}
end

defimpl String.Chars, for: ClaudeCode.Content.MCPToolUseBlock do
  def to_string(%{server_name: server, name: name}), do: "[mcp: #{server}/#{name}]"
end
