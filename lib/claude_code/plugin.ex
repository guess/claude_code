defmodule ClaudeCode.Plugin do
  @moduledoc """
  Plugin management functions wrapping the `claude plugin` CLI commands.

  Provides functions to install, uninstall, enable, disable, update, list,
  and validate plugins from configured marketplaces.

  All functions resolve the CLI binary via `ClaudeCode.Adapter.Port.Resolver` and execute
  commands synchronously via `ClaudeCode.System`.

  > **Note:** Remote node support is not yet implemented — these commands run on
  > the local machine only.

  ## Examples

      # List installed plugins
      {:ok, plugins} = ClaudeCode.Plugin.list()

      # Install a plugin from a marketplace
      {:ok, _} = ClaudeCode.Plugin.install("code-simplifier@claude-plugins-official")

      # Enable/disable a plugin
      {:ok, _} = ClaudeCode.Plugin.enable("code-simplifier@claude-plugins-official")
      {:ok, _} = ClaudeCode.Plugin.disable("code-simplifier@claude-plugins-official")
  """

  alias ClaudeCode.Plugin.CLI, as: PluginCLI

  defstruct [
    :id,
    :version,
    :scope,
    :enabled,
    :install_path,
    :installed_at,
    :last_updated,
    :project_path,
    :mcp_servers
  ]

  @type scope :: :user | :project | :local

  @type t :: %__MODULE__{
          id: String.t(),
          version: String.t() | nil,
          scope: scope() | nil,
          enabled: boolean(),
          install_path: String.t() | nil,
          installed_at: String.t() | nil,
          last_updated: String.t() | nil,
          project_path: String.t() | nil,
          mcp_servers: map() | nil
        }

  @doc """
  Lists installed plugins.

  Returns a list of `%ClaudeCode.Plugin{}` structs parsed from
  `claude plugin list --json`.

  ## Examples

      {:ok, plugins} = ClaudeCode.Plugin.list()
      Enum.each(plugins, fn p -> IO.puts("\#{p.id} (enabled: \#{p.enabled})") end)
  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, String.t()}
  def list(opts \\ []) do
    PluginCLI.run(["plugin", "list", "--json"], opts, &parse_list/1)
  end

  @doc """
  Installs a plugin from available marketplaces.

  Use `plugin@marketplace` format for a specific marketplace, or just `plugin`
  to search all configured marketplaces.

  ## Options

    * `:scope` - Installation scope: `:user` (default), `:project`, or `:local`

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.install("code-simplifier@claude-plugins-official")
      {:ok, _} = ClaudeCode.Plugin.install("my-plugin@my-org", scope: :project)
  """
  @spec install(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def install(plugin_id, opts \\ []) do
    args = ["plugin", "install"] ++ PluginCLI.scope_args(opts) ++ [plugin_id]
    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  @doc """
  Uninstalls an installed plugin.

  ## Options

    * `:scope` - Uninstall from scope: `:user` (default), `:project`, or `:local`

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.uninstall("code-simplifier@claude-plugins-official")
  """
  @spec uninstall(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def uninstall(plugin_id, opts \\ []) do
    args = ["plugin", "uninstall"] ++ PluginCLI.scope_args(opts) ++ [plugin_id]
    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  @doc """
  Enables a disabled plugin.

  ## Options

    * `:scope` - Scope: `:user`, `:project`, or `:local` (default: auto-detect)

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.enable("code-simplifier@claude-plugins-official")
  """
  @spec enable(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def enable(plugin_id, opts \\ []) do
    args = ["plugin", "enable"] ++ PluginCLI.scope_args(opts) ++ [plugin_id]
    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  @doc """
  Disables an enabled plugin.

  ## Options

    * `:scope` - Scope: `:user`, `:project`, or `:local` (default: auto-detect)

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.disable("code-simplifier@claude-plugins-official")
  """
  @spec disable(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def disable(plugin_id, opts \\ []) do
    args = ["plugin", "disable"] ++ PluginCLI.scope_args(opts) ++ [plugin_id]
    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  @doc """
  Disables all enabled plugins.

  ## Options

    * `:scope` - Scope: `:user`, `:project`, or `:local` (default: auto-detect)

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.disable_all()
      {:ok, _} = ClaudeCode.Plugin.disable_all(scope: :project)
  """
  @spec disable_all(keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def disable_all(opts \\ []) do
    args = ["plugin", "disable", "--all"] ++ PluginCLI.scope_args(opts)
    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  @doc """
  Updates a plugin to the latest version.

  A session restart is required for updates to take effect.

  ## Options

    * `:scope` - Scope: `:user`, `:project`, `:local`, or `:managed`

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.update("code-simplifier@claude-plugins-official")
  """
  @spec update(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def update(plugin_id, opts \\ []) do
    args = ["plugin", "update"] ++ PluginCLI.scope_args(opts) ++ [plugin_id]
    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  # -- Private: JSON parsing ---------------------------------------------------

  defp parse_list(output) do
    case Jason.decode(output) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.map(items, &from_json/1)}

      {:error, _reason} ->
        {:error, "Failed to parse plugin list JSON: #{String.trim(output)}"}
    end
  end

  defp from_json(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      version: map["version"],
      scope: parse_scope(map["scope"]),
      enabled: map["enabled"] || false,
      install_path: map["installPath"],
      installed_at: map["installedAt"],
      last_updated: map["lastUpdated"],
      project_path: map["projectPath"],
      mcp_servers: map["mcpServers"]
    }
  end

  defp parse_scope("user"), do: :user
  defp parse_scope("project"), do: :project
  defp parse_scope("local"), do: :local
  defp parse_scope(_other), do: nil
end
