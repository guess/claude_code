defmodule ClaudeCode.Message.System do
  @moduledoc """
  Represents a system message from the Claude CLI.

  System messages are initialization messages that provide session setup information
  including available tools, MCP servers, model, and permission mode.

  Can be one of two subtypes:
  - `init` - Initial system message with session setup information
  - `compact_boundary` - Indicates a conversation compaction boundary

  Matches the official SDK schema:
  ```
  # For init subtype:
  {
    type: "system",
    subtype: "init",
    uuid: string,
    apiKeySource: string,
    cwd: string,
    session_id: string,
    tools: string[],
    mcp_servers: { name: string, status: string }[],
    model: string,
    permissionMode: "default" | "acceptEdits" | "bypassPermissions" | "plan",
    slashCommands: string[],
    outputStyle: string
  }

  # For compact_boundary subtype:
  {
    type: "system",
    subtype: "compact_boundary",
    uuid: string,
    session_id: string,
    compact_metadata: {
      trigger: "manual" | "auto",
      pre_tokens: number
    }
  }
  ```
  """

  alias ClaudeCode.Types

  @enforce_keys [
    :type,
    :subtype,
    :uuid,
    :session_id
  ]
  defstruct [
    :type,
    :subtype,
    :uuid,
    :session_id,
    :cwd,
    :tools,
    :mcp_servers,
    :model,
    :permission_mode,
    :api_key_source,
    :slash_commands,
    :output_style,
    :compact_metadata
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :init | :compact_boundary,
          uuid: String.t(),
          session_id: Types.session_id(),
          cwd: String.t() | nil,
          tools: [String.t()] | nil,
          mcp_servers: [Types.mcp_server()] | nil,
          model: String.t() | nil,
          permission_mode: Types.permission_mode() | nil,
          api_key_source: String.t() | nil,
          slash_commands: [String.t()] | nil,
          output_style: String.t() | nil,
          compact_metadata: %{trigger: String.t(), pre_tokens: non_neg_integer()} | nil
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
    subtype = json["subtype"]

    case subtype do
      "init" -> parse_init(json)
      "compact_boundary" -> parse_compact_boundary(json)
      _ -> {:error, :invalid_message_type}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a System message.
  """
  @spec system_message?(any()) :: boolean()
  def system_message?(%__MODULE__{type: :system}), do: true
  def system_message?(_), do: false

  # Private functions

  defp parse_init(json) do
    required_fields = [
      "subtype",
      "cwd",
      "session_id",
      "tools",
      "mcp_servers",
      "model",
      "permissionMode",
      "apiKeySource"
    ]

    missing = Enum.filter(required_fields, &(not Map.has_key?(json, &1)))

    if Enum.empty?(missing) do
      message = %__MODULE__{
        type: :system,
        subtype: :init,
        uuid: json["uuid"],
        cwd: json["cwd"],
        session_id: json["session_id"],
        tools: json["tools"],
        mcp_servers: parse_mcp_servers(json["mcp_servers"]),
        model: json["model"],
        permission_mode: parse_permission_mode(json["permissionMode"]),
        api_key_source: json["apiKeySource"],
        slash_commands: json["slashCommands"],
        output_style: json["outputStyle"],
        compact_metadata: nil
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  defp parse_compact_boundary(json) do
    required_fields = [
      "subtype",
      "uuid",
      "session_id",
      "compact_metadata"
    ]

    missing = Enum.filter(required_fields, &(not Map.has_key?(json, &1)))

    if Enum.empty?(missing) do
      message = %__MODULE__{
        type: :system,
        subtype: :compact_boundary,
        uuid: json["uuid"],
        session_id: json["session_id"],
        compact_metadata: parse_compact_metadata(json["compact_metadata"]),
        cwd: nil,
        tools: nil,
        mcp_servers: nil,
        model: nil,
        permission_mode: nil,
        api_key_source: nil,
        slash_commands: nil,
        output_style: nil
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

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

  defp parse_compact_metadata(metadata) when is_map(metadata) do
    %{
      trigger: metadata["trigger"],
      pre_tokens: metadata["pre_tokens"] || 0
    }
  end

  defp parse_compact_metadata(_), do: nil
end
