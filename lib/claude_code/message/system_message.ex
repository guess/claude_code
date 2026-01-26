defmodule ClaudeCode.Message.SystemMessage do
  @moduledoc """
  Represents a system initialization message from the Claude CLI.

  System messages provide session setup information including available tools,
  MCP servers, model, and permission mode.

  For conversation compaction boundaries, use `ClaudeCode.Message.CompactBoundaryMessage`.

  Matches the official SDK schema:
  ```
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
    slash_commands: string[],
    output_style: string,
    claude_code_version: string,
    agents: string[],
    skills: string[],
    plugins: string[]
  }
  ```
  """

  alias ClaudeCode.Types

  @enforce_keys [
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
    :claude_code_version,
    slash_commands: [],
    output_style: "default",
    agents: [],
    skills: [],
    plugins: []
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :init,
          uuid: String.t(),
          cwd: String.t(),
          session_id: Types.session_id(),
          tools: [String.t()],
          mcp_servers: [Types.mcp_server()],
          model: String.t(),
          permission_mode: Types.permission_mode(),
          api_key_source: String.t(),
          claude_code_version: String.t() | nil,
          slash_commands: [String.t()],
          output_style: String.t(),
          agents: [String.t()],
          skills: [String.t()],
          plugins: [String.t()]
        }

  @doc """
  Creates a new SystemMessage from JSON data.

  ## Examples

      iex> SystemMessage.new(%{"type" => "system", "subtype" => "init", ...})
      {:ok, %SystemMessage{...}}

      iex> SystemMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, :invalid_message_type | {:missing_fields, [atom()]}}
  def new(%{"type" => "system", "subtype" => "init"} = json) do
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
        claude_code_version: json["claude_code_version"],
        slash_commands: json["slash_commands"] || [],
        output_style: json["output_style"] || "default",
        agents: json["agents"] || [],
        skills: json["skills"] || [],
        plugins: json["plugins"] || []
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a SystemMessage.
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

defimpl Jason.Encoder, for: ClaudeCode.Message.SystemMessage do
  def encode(message, opts) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Message.SystemMessage do
  def encode(message, encoder) do
    message
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
