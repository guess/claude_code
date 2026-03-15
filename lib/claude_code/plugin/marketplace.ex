defmodule ClaudeCode.Plugin.Marketplace do
  @moduledoc """
  Marketplace management functions wrapping `claude plugin marketplace` CLI commands.

  Marketplaces are catalogs that define where plugins can be discovered and installed from.
  They can reference plugins from GitHub repos, git URLs, npm packages, and more.

  All functions resolve the CLI binary via `ClaudeCode.Adapter.Port.Resolver` and execute
  commands synchronously via the system command abstraction.

  > **Note:** Remote node support is not yet implemented — these commands run on
  > the local machine only.

  ## Examples

      # List configured marketplaces
      {:ok, marketplaces} = ClaudeCode.Plugin.Marketplace.list()

      # Add a marketplace from GitHub
      {:ok, _output} = ClaudeCode.Plugin.Marketplace.add("owner/repo")

      # Remove a marketplace
      {:ok, _output} = ClaudeCode.Plugin.Marketplace.remove("my-marketplace")

      # Update all marketplaces
      {:ok, _output} = ClaudeCode.Plugin.Marketplace.update()
  """

  alias ClaudeCode.Plugin.CLI, as: PluginCLI

  defstruct [:name, :source, :repo, :install_location]

  @type t :: %__MODULE__{
          name: String.t(),
          source: String.t(),
          repo: String.t() | nil,
          install_location: String.t() | nil
        }

  @type scope :: :user | :project | :local

  @doc """
  Lists all configured marketplaces.

  Returns a list of `%ClaudeCode.Plugin.Marketplace{}` structs parsed from
  `claude plugin marketplace list --json`.

  ## Examples

      {:ok, marketplaces} = ClaudeCode.Plugin.Marketplace.list()
      Enum.each(marketplaces, fn m -> IO.puts("\#{m.name} (\#{m.source})") end)
  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, String.t()}
  def list(opts \\ []) do
    PluginCLI.run(["plugin", "marketplace", "list", "--json"], opts, &parse_list/1)
  end

  @doc """
  Adds a marketplace from a URL, path, or GitHub repo.

  Accepts the same source formats as the CLI: GitHub shorthand (`"owner/repo"`),
  full git URLs, or local paths.

  ## Options

    * `:scope` - Where to declare the marketplace: `:user` (default), `:project`, or `:local`
    * `:sparse` - List of paths for git sparse-checkout (for monorepos)

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.Marketplace.add("owner/repo")
      {:ok, _} = ClaudeCode.Plugin.Marketplace.add("https://gitlab.com/org/plugins.git", scope: :project)
      {:ok, _} = ClaudeCode.Plugin.Marketplace.add("owner/monorepo", sparse: [".claude-plugin", "plugins"])
  """
  @spec add(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def add(source, opts \\ []) do
    args =
      ["plugin", "marketplace", "add"] ++ PluginCLI.scope_args(opts) ++ sparse_args(opts) ++ [source]

    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  @doc """
  Removes a configured marketplace by name.

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.Marketplace.remove("my-marketplace")
  """
  @spec remove(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def remove(name, opts \\ []) do
    PluginCLI.run(["plugin", "marketplace", "remove", name], opts, &PluginCLI.ok_trimmed/1)
  end

  @doc """
  Updates marketplace(s) from their source.

  When called with `nil`, updates all marketplaces. When called with a name,
  updates only that marketplace.

  ## Examples

      {:ok, _} = ClaudeCode.Plugin.Marketplace.update(nil)
      {:ok, _} = ClaudeCode.Plugin.Marketplace.update("my-marketplace")
  """
  @spec update(String.t() | nil, keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def update(name, opts \\ []) do
    args = ["plugin", "marketplace", "update"] ++ if(name, do: [name], else: [])
    PluginCLI.run(args, opts, &PluginCLI.ok_trimmed/1)
  end

  # -- Private ----------------------------------------------------------------

  defp sparse_args(opts) do
    case Keyword.get(opts, :sparse) do
      nil -> []
      paths when is_list(paths) -> ["--sparse" | paths]
    end
  end

  defp parse_list(output) do
    case Jason.decode(output) do
      {:ok, items} when is_list(items) ->
        {:ok, Enum.map(items, &from_json/1)}

      {:error, _reason} ->
        {:error, "Failed to parse marketplace list JSON: #{String.trim(output)}"}
    end
  end

  defp from_json(map) when is_map(map) do
    %__MODULE__{
      name: map["name"],
      source: map["source"],
      repo: map["repo"],
      install_location: map["installLocation"]
    }
  end
end
