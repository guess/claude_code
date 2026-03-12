# Plugin Management API & Marketplace Plugin Type

## Summary

Two additions to the SDK:

1. **Marketplace plugin type in options** — Allow enabling marketplace plugins via the `:plugins` session option, merging into `settings.enabledPlugins`
2. **Plugin management API** — `ClaudeCode.Plugin` and `ClaudeCode.Plugin.Marketplace` modules wrapping `claude plugin` CLI commands

## 1. Marketplace Plugin Type in Options

### Usage

```elixir
ClaudeCode.start_link(
  plugins: [
    # Local plugins (existing behavior)
    "./my-local-plugin",
    %{type: :local, path: "./another-plugin"},

    # Marketplace plugins (new)
    "code-simplifier@claude-plugins-official",
    %{type: :marketplace, id: "code-simplifier@claude-plugins-official"}
  ]
)
```

### String Detection

Strings containing `@` are treated as marketplace plugin IDs. Strings without `@` are treated as local filesystem paths. The `name@marketplace` format is the CLI's canonical plugin ID format.

### Implementation

A new `preprocess_plugins/1` step in `CLI.Command` (same pattern as `preprocess_sandbox/1`):

1. Partition plugins into local and marketplace lists
2. Local plugins remain in `:plugins` for `convert_option/2` → `--plugin-dir` flags
3. Marketplace plugins are collected into `%{"enabledPlugins" => %{"id" => true}}`
4. The `enabledPlugins` map is deep-merged into the existing `:settings` option
5. If `:settings` already contains `enabledPlugins`, the maps are merged (union)

### Options Validation

The NimbleOptions type stays `{:list, {:or, [:string, :map]}}`. Maps accept both `type: :local` (with `path`) and `type: :marketplace` (with `id`).

## 2. Plugin Management API

### `ClaudeCode.Plugin`

```elixir
defmodule ClaudeCode.Plugin do
  @moduledoc """
  Plugin management functions wrapping the `claude plugin` CLI commands.

  All functions resolve the CLI binary via `ClaudeCode.CLI` and execute
  commands synchronously via `System.cmd/3`.

  Remote node support is not yet implemented — these commands run on
  the local machine only.
  """

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
  @type t :: %__MODULE__{}

  # Returns {:ok, [%Plugin{}]} | {:error, String.t()}
  def list(opts \\ [])

  # Returns {:ok, String.t()} | {:error, String.t()}
  # Options: scope: :user | :project | :local
  def install(plugin_id, opts \\ [])
  def uninstall(plugin_id, opts \\ [])
  def enable(plugin_id, opts \\ [])
  def disable(plugin_id, opts \\ [])
  def disable_all(opts \\ [])
  def update(plugin_id, opts \\ [])

  # Returns {:ok, String.t()} | {:error, String.t()}
  def validate(path)
end
```

### `ClaudeCode.Plugin.Marketplace`

```elixir
defmodule ClaudeCode.Plugin.Marketplace do
  @moduledoc """
  Marketplace management functions wrapping `claude plugin marketplace` CLI commands.

  Remote node support is not yet implemented.
  """

  defstruct [:name, :source, :repo, :install_location]

  @type t :: %__MODULE__{}

  # Returns {:ok, [%Marketplace{}]} | {:error, String.t()}
  def list(opts \\ [])

  # Returns {:ok, String.t()} | {:error, String.t()}
  # Options: scope: :user | :project | :local, sparse: [String.t()]
  def add(source, opts \\ [])

  # Returns {:ok, String.t()} | {:error, String.t()}
  def remove(name)

  # nil = update all marketplaces
  # Returns {:ok, String.t()} | {:error, String.t()}
  def update(name \\ nil)
end
```

### CLI Execution

Both modules share a private helper pattern:

1. Resolve `claude` binary via `ClaudeCode.CLI`
2. Run command via `System.cmd/3`
3. For `--json` commands: parse JSON, map to structs (using `safe_atomize_keys`)
4. For non-JSON commands: return raw output string
5. Non-zero exit code → `{:error, stderr_output}`

### Struct Field Mapping

**Plugin** (from `claude plugin list --json`):

| JSON field       | Struct field     | Type              |
|------------------|------------------|-------------------|
| `id`             | `:id`            | `String.t()`      |
| `version`        | `:version`       | `String.t()`      |
| `scope`          | `:scope`         | `:user \| :project \| :local` |
| `enabled`        | `:enabled`       | `boolean()`       |
| `installPath`    | `:install_path`  | `String.t()`      |
| `installedAt`    | `:installed_at`  | `String.t()`      |
| `lastUpdated`    | `:last_updated`  | `String.t()`      |
| `projectPath`    | `:project_path`  | `String.t() \| nil` |
| `mcpServers`     | `:mcp_servers`   | `map() \| nil`    |

**Marketplace** (from `claude plugin marketplace list --json`):

| JSON field         | Struct field        | Type         |
|--------------------|---------------------|--------------|
| `name`             | `:name`             | `String.t()` |
| `source`           | `:source`           | `String.t()` |
| `repo`             | `:repo`             | `String.t()` |
| `installLocation`  | `:install_location` | `String.t()` |

## Error Handling

All functions return `{:ok, result}` / `{:error, reason}` tuples. Errors contain the CLI's stderr output as a string. Structured error atoms may be added later if patterns emerge.

## Future Work

- Remote node support via optional `node: :"name@host"` parameter
- Structured error types for common failure modes
- `plugin list --available` support for discovering uninstalled plugins
