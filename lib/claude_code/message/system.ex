defmodule ClaudeCode.Message.System do
  @moduledoc """
  Represents a system message from the Claude CLI.

  System messages are initialization messages that provide session setup information
  including available tools, MCP servers, model, and permission mode.

  Matches the official SDK schema:
  ```
  {
    type: "system",
    subtype: "init",
    apiKeySource: string,
    cwd: string,
    session_id: string,
    tools: string[],
    mcp_servers: { name: string, status: string }[],
    model: string,
    permissionMode: "default" | "acceptEdits" | "bypassPermissions" | "plan"
  }
  ```
  """

  alias ClaudeCode.Types

  @enforce_keys [
    :type,
    :subtype,
    :uuid,
    :cwd,
    :session_id,
    :tools,
    :mcp_servers,
    :model,
    :permission_mode,
    :api_key_source,
    :slash_commands,
    :output_style
  ]
  defstruct [
    :type,
    :subtype,
    :uuid,
    :cwd,
    :session_id,
    :tools,
    :mcp_servers,
    :model,
    :permission_mode,
    :api_key_source,
    :slash_commands,
    :output_style
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :init,
          uuid: String.t(),
          cwd: String.t(),
          session_id: Types.session_id(),
          tools: [String.t()],
          mcp_servers: [Types.mcp_server()],
          model: Types.model(),
          permission_mode: Types.permission_mode(),
          api_key_source: String.t(),
          slash_commands: [String.t()],
          output_style: String.t()
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
    required_fields = [
      "subtype",
      "uuid",
      "cwd",
      "session_id",
      "tools",
      "mcp_servers",
      "model",
      "permissionMode",
      "apiKeySource",
      "slashCommands",
      "outputStyle"
    ]

    missing = Enum.filter(required_fields, &(not Map.has_key?(json, &1)))

    if Enum.empty?(missing) do
      message = %__MODULE__{
        type: :system,
        subtype: String.to_atom(json["subtype"]),
        uuid: json["uuid"],
        cwd: json["cwd"],
        session_id: json["session_id"],
        tools: json["tools"],
        mcp_servers: parse_mcp_servers(json["mcp_servers"]),
        model: json["model"],
        permission_mode: parse_permission_mode(json["permissionMode"]),
        api_key_source: json["apiKeySource"],
        slash_commands: json["slashCommands"],
        output_style: json["outputStyle"]
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
  @spec system_message?(any()) :: boolean()
  def system_message?(%__MODULE__{type: :system}), do: true
  def system_message?(_), do: false

  defp parse_mcp_servers(servers) when is_list(servers) do
    Enum.map(servers, fn server ->
      %{
        name: server["name"],
        status: server["status"]
      }
    end)
  end

  defp parse_permission_mode("default"), do: :default
  defp parse_permission_mode("acceptEdits"), do: :accept_edits
  defp parse_permission_mode("bypassPermissions"), do: :bypass_permissions
  defp parse_permission_mode("plan"), do: :plan
  defp parse_permission_mode(_), do: :default
end
