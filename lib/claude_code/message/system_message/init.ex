defmodule ClaudeCode.Message.SystemMessage.Init do
  @moduledoc """
  Represents the session initialization system message from the Claude CLI.

  The init message is the first message received when a session starts,
  containing the available tools, model, MCP servers, and session configuration.
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.MCP.ServerStatus

  @enforce_keys [
    :type,
    :subtype,
    :session_id
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
    plugins: [],
    fast_mode_state: nil
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :init,
          uuid: String.t() | nil,
          cwd: String.t() | nil,
          session_id: String.t(),
          tools: [String.t()] | nil,
          mcp_servers: [ServerStatus.t()] | nil,
          model: String.t() | nil,
          permission_mode: ClaudeCode.PermissionMode.t() | nil,
          api_key_source: String.t() | nil,
          claude_code_version: String.t() | nil,
          slash_commands: [String.t()],
          output_style: String.t(),
          agents: [String.t()],
          skills: [String.t()],
          plugins: [%{name: String.t(), path: String.t()} | String.t()],
          fast_mode_state: String.t() | nil
        }

  @spec new(map()) :: {:ok, t()} | {:error, :invalid_message_type | {:missing_fields, [atom()]}}
  def new(%{"type" => "system", "subtype" => "init"} = json) do
    required_fields = [
      "subtype",
      "cwd",
      "session_id",
      "tools",
      "mcp_servers",
      "model",
      "permission_mode",
      "api_key_source"
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
        permission_mode: ClaudeCode.PermissionMode.parse(json["permission_mode"], :default),
        api_key_source: json["api_key_source"],
        claude_code_version: json["claude_code_version"],
        slash_commands: json["slash_commands"] || [],
        output_style: json["output_style"] || "default",
        agents: json["agents"] || [],
        skills: json["skills"] || [],
        plugins: parse_plugins(json["plugins"]),
        fast_mode_state: json["fast_mode_state"]
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is an Init message.
  """
  @spec init?(any()) :: boolean()
  def init?(%__MODULE__{type: :system, subtype: :init}), do: true
  def init?(_), do: false

  defp parse_mcp_servers(servers) when is_list(servers) do
    Enum.map(servers, &ServerStatus.new/1)
  end

  defp parse_mcp_servers(_), do: nil

  defp parse_plugins(plugins) when is_list(plugins) do
    plugins
    |> Enum.map(fn
      %{"name" => name, "path" => path} -> %{name: name, path: path}
      plugin when is_binary(plugin) -> plugin
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_plugins(_), do: []
end
