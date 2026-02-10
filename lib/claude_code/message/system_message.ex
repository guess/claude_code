defmodule ClaudeCode.Message.SystemMessage do
  @moduledoc """
  Represents a system message from the Claude CLI.

  System messages cover multiple subtypes:

  - `:init` - Session initialization with tools, model, MCP servers, etc.
  - `:hook_started` - Hook execution started
  - `:hook_response` - Hook execution completed with output
  - Any future subtypes the CLI may add

  For `:init` messages, all the dedicated fields (tools, model, mcp_servers, etc.)
  are populated. For other subtypes, extra fields are stored in the `data` map.

  For conversation compaction boundaries, use `ClaudeCode.Message.CompactBoundaryMessage`.

  Mirrors the Python SDK's generic approach: `SystemMessage(subtype=str, data=dict)`.
  """

  alias ClaudeCode.Types

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
    fast_mode_state: nil,
    data: %{}
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: atom(),
          uuid: String.t() | nil,
          cwd: String.t() | nil,
          session_id: Types.session_id(),
          tools: [String.t()] | nil,
          mcp_servers: [Types.mcp_server()] | nil,
          model: String.t() | nil,
          permission_mode: Types.permission_mode() | nil,
          api_key_source: String.t() | nil,
          claude_code_version: String.t() | nil,
          slash_commands: [String.t()],
          output_style: String.t(),
          agents: [String.t()],
          skills: [String.t()],
          plugins: [Types.plugin()],
          fast_mode_state: String.t() | nil,
          data: map()
        }

  @doc """
  Creates a new SystemMessage from JSON data.

  For `init` subtypes, validates required fields and populates dedicated struct fields.
  For all other subtypes, stores extra fields in the `data` map.

  ## Examples

      iex> SystemMessage.new(%{"type" => "system", "subtype" => "init", ...})
      {:ok, %SystemMessage{subtype: :init, ...}}

      iex> SystemMessage.new(%{"type" => "system", "subtype" => "hook_started", ...})
      {:ok, %SystemMessage{subtype: :hook_started, data: %{...}}}

      iex> SystemMessage.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, :invalid_message_type | :missing_session_id | {:missing_fields, [atom()]}}
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
        plugins: parse_plugins(json["plugins"]),
        fast_mode_state: json["fast_mode_state"]
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(%{"type" => "system", "subtype" => subtype} = json) do
    case json do
      %{"session_id" => session_id} ->
        data =
          json
          |> Map.drop(["type", "subtype", "session_id", "uuid"])
          |> atomize_top_level_keys()

        {:ok,
         %__MODULE__{
           type: :system,
           subtype: String.to_atom(subtype),
           session_id: session_id,
           uuid: json["uuid"],
           data: data
         }}

      _ ->
        {:error, :missing_session_id}
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

  defp parse_permission_mode("default"), do: :default
  defp parse_permission_mode("acceptEdits"), do: :accept_edits
  defp parse_permission_mode("bypassPermissions"), do: :bypass_permissions
  defp parse_permission_mode("delegate"), do: :delegate
  defp parse_permission_mode("dontAsk"), do: :dont_ask
  defp parse_permission_mode("plan"), do: :plan
  defp parse_permission_mode(_), do: :default

  defp atomize_top_level_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
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
