defmodule ClaudeCode.Message.SystemMessage.PluginInstall do
  @moduledoc """
  Represents a plugin install system message from the Claude CLI.

  Emitted during plugin installation lifecycle events, tracking the
  progress and outcome of a plugin installation.

  ## Fields

  - `:type` - Always `:system`
  - `:subtype` - Always `:plugin_install`
  - `:status` - Installation status atom (`:started`, `:installed`, `:failed`, or `:completed`)
  - `:name` - Optional plugin name
  - `:error` - Optional error message if installation failed
  - `:uuid` - Message UUID
  - `:session_id` - Session identifier

  ## JSON Format

  ```json
  {
    "type": "system",
    "subtype": "plugin_install",
    "status": "installed",
    "name": "my-plugin",
    "uuid": "...",
    "session_id": "..."
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  @enforce_keys [:type, :subtype, :session_id]
  defstruct [
    :type,
    :subtype,
    :status,
    :name,
    :error,
    :uuid,
    :session_id
  ]

  @type t :: %__MODULE__{
          type: :system,
          subtype: :plugin_install,
          status: :started | :installed | :failed | :completed | nil,
          name: String.t() | nil,
          error: String.t() | nil,
          uuid: String.t() | nil,
          session_id: String.t()
        }

  @doc """
  Creates a new PluginInstall from JSON data.

  The `"status"` string is parsed to an atom (`:started`, `:installed`, `:failed`, or `:completed`).
  Unknown values are parsed to `nil`.

  ## Examples

      iex> PluginInstall.new(%{
      ...>   "type" => "system",
      ...>   "subtype" => "plugin_install",
      ...>   "status" => "installed",
      ...>   "name" => "my-plugin",
      ...>   "session_id" => "session-1"
      ...> })
      {:ok, %PluginInstall{type: :system, subtype: :plugin_install, status: :installed, ...}}

      iex> PluginInstall.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(%{"type" => "system", "subtype" => "plugin_install", "session_id" => session_id} = json) do
    {:ok,
     %__MODULE__{
       type: :system,
       subtype: :plugin_install,
       status: parse_status(json["status"]),
       name: json["name"],
       error: json["error"],
       uuid: json["uuid"],
       session_id: session_id
     }}
  end

  def new(%{"type" => "system", "subtype" => "plugin_install"}), do: {:error, :missing_required_fields}
  def new(_), do: {:error, :invalid_message_type}

  @doc """
  Type guard to check if a value is a PluginInstall.
  """
  @spec plugin_install?(any()) :: boolean()
  def plugin_install?(%__MODULE__{type: :system, subtype: :plugin_install}), do: true
  def plugin_install?(_), do: false

  defp parse_status("started"), do: :started
  defp parse_status("installed"), do: :installed
  defp parse_status("failed"), do: :failed
  defp parse_status("completed"), do: :completed
  defp parse_status(_), do: nil
end
