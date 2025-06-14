defmodule ClaudeCode.Message.System do
  @moduledoc """
  Represents a system message from the Claude CLI.

  System messages are initialization messages that provide session setup information
  including available tools, MCP servers, model, and permission mode.
  """

  @enforce_keys [:type, :subtype, :cwd, :session_id, :tools, :mcp_servers, :model, :permission_mode, :api_key_source]
  defstruct [
    :type,
    :subtype,
    :cwd,
    :session_id,
    :tools,
    :mcp_servers,
    :model,
    :permission_mode,
    :api_key_source
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :init,
          cwd: String.t(),
          session_id: String.t(),
          tools: [String.t()],
          mcp_servers: [mcp_server()],
          model: String.t(),
          permission_mode: :default | :bypass_permissions,
          api_key_source: String.t()
        }

  @type mcp_server :: %{
          name: String.t(),
          status: String.t()
        }

  @doc """
  Creates a new System message from JSON data.

  ## Examples

      iex> System.new(%{"type" => "system", "subtype" => "init", ...})
      {:ok, %System{...}}
      
      iex> System.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, :invalid_message_type | {:missing_fields, [atom()]}}
  def new(%{"type" => "system"} = json) do
    required_fields = ["subtype", "cwd", "session_id", "tools", "mcp_servers", "model", "permissionMode", "apiKeySource"]

    missing = Enum.filter(required_fields, &(not Map.has_key?(json, &1)))

    if Enum.empty?(missing) do
      message = %__MODULE__{
        type: :system,
        subtype: String.to_atom(json["subtype"]),
        cwd: json["cwd"],
        session_id: json["session_id"],
        tools: json["tools"],
        mcp_servers: parse_mcp_servers(json["mcp_servers"]),
        model: json["model"],
        permission_mode: parse_permission_mode(json["permissionMode"]),
        api_key_source: json["apiKeySource"]
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a System message.
  """
  @spec is_system_message?(any()) :: boolean()
  def is_system_message?(%__MODULE__{type: :system}), do: true
  def is_system_message?(_), do: false

  defp parse_mcp_servers(servers) when is_list(servers) do
    Enum.map(servers, fn server ->
      %{
        name: server["name"],
        status: server["status"]
      }
    end)
  end

  defp parse_permission_mode("default"), do: :default
  defp parse_permission_mode("bypassPermissions"), do: :bypass_permissions
  defp parse_permission_mode(mode), do: mode
end
