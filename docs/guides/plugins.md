# Plugins

Load custom plugins to extend Claude Code with commands, agents, skills, and hooks through the Agent SDK.

> **Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/plugins). Examples are adapted for Elixir.

Plugins allow you to extend Claude Code with custom functionality that can be shared across projects. Through the Elixir SDK, you can load plugins from local directories or enable marketplace plugins, and programmatically manage plugin installation and marketplaces.

## What are plugins?

Plugins are packages of Claude Code extensions that can include:

- **Commands** -- Custom slash commands
- **Agents** -- Specialized subagents for specific tasks
- **Skills** -- Model-invoked capabilities that Claude uses autonomously
- **Hooks** -- Event handlers that respond to tool use and other events
- **MCP servers** -- External tool integrations via Model Context Protocol

For complete information on plugin structure and how to create plugins, see [Plugins](https://code.claude.com/docs/en/plugins).

## Loading plugins

### Local plugins

Load local plugins by providing their file system paths. Each local plugin path is passed to the CLI as a `--plugin-dir` flag.

```elixir
# As simple path strings
{:ok, session} = ClaudeCode.start_link(
  plugins: ["./my-plugin", "/absolute/path/to/another-plugin"]
)

# As typed configuration maps
{:ok, session} = ClaudeCode.start_link(
  plugins: [
    %{type: :local, path: "./my-plugin"},
    %{type: :local, path: "/absolute/path/to/another-plugin"}
  ]
)
```

### Marketplace plugins

Enable plugins from configured marketplaces using the `name@marketplace` format. Marketplace plugins are merged into `settings.enabledPlugins` and require that the marketplace is already configured (see [Managing marketplaces](#managing-marketplaces)).

```elixir
# As simple strings (@ indicates a marketplace plugin)
{:ok, session} = ClaudeCode.start_link(
  plugins: ["code-simplifier@claude-plugins-official"]
)

# As typed configuration maps
{:ok, session} = ClaudeCode.start_link(
  plugins: [
    %{type: :marketplace, id: "code-simplifier@claude-plugins-official"}
  ]
)
```

### Mixed formats

Local and marketplace plugins can be freely combined:

```elixir
{:ok, session} = ClaudeCode.start_link(
  plugins: [
    "./my-local-plugin",
    "code-simplifier@claude-plugins-official",
    %{type: :local, path: "./another-plugin"},
    %{type: :marketplace, id: "pr-review-toolkit@claude-plugins-official"}
  ]
)
```

Strings containing `@` are treated as marketplace plugin IDs. Strings without `@` are treated as local filesystem paths. See `ClaudeCode.Options` for the full schema.

### Path specifications

Plugin paths can be:

- **Relative paths** -- Resolved relative to your current working directory (for example, `"./plugins/my-plugin"`)
- **Absolute paths** -- Full file system paths (for example, `"/home/user/plugins/my-plugin"`)

> **Note:** The path should point to the plugin's root directory (the directory containing `.claude-plugin/plugin.json`).

### Query-level overrides

Plugins can also be specified (or overridden) at query time:

```elixir
session
|> ClaudeCode.stream("Hello",
  plugins: [
    %{type: :local, path: "./dev-plugins/experimental"}
  ]
)
|> Stream.run()
```

## Verifying plugin installation

When plugins load successfully, they appear in the system initialization message (`ClaudeCode.Message.SystemMessage`). You can verify that your plugins are available by inspecting the `plugins` and `slash_commands` fields:

```elixir
alias ClaudeCode.Message.SystemMessage

session
|> ClaudeCode.stream("Hello",
  plugins: [%{type: :local, path: "./my-plugin"}]
)
|> ClaudeCode.Stream.filter_type(:system)
|> Enum.each(fn
  %SystemMessage{subtype: :init, plugins: plugins, slash_commands: commands} ->
    # Check loaded plugins
    IO.puts("Loaded plugins:")

    Enum.each(plugins, fn
      %{name: name, path: path} -> IO.puts("  #{name} (#{path})")
      name when is_binary(name) -> IO.puts("  #{name}")
    end)

    # Check available commands (plugins add namespaced commands)
    IO.puts("Available commands:")
    Enum.each(commands, &IO.puts("  #{&1}"))

  _ ->
    :ok
end)
```

The `ClaudeCode.Message.SystemMessage` struct includes these plugin-related fields:

| Field            | Type                        | Description                                                  |
| :--------------- | :-------------------------- | :----------------------------------------------------------- |
| `plugins`        | list of maps or strings     | Loaded plugins, each with `:name` and `:path` keys           |
| `slash_commands` | list of strings             | All available slash commands, including plugin-namespaced ones |
| `skills`         | list of strings             | Available skills, including those from plugins                |
| `tools`          | list of strings             | Available tools, including those from plugin MCP servers      |

## Using plugin commands

Commands from plugins are automatically namespaced with the plugin name to avoid conflicts. The format is `plugin-name:command-name`.

```elixir
alias ClaudeCode.Message.ResultMessage

# Invoke a plugin command by using the namespaced format
result =
  session
  |> ClaudeCode.stream("/my-plugin:greet",
    plugins: [%{type: :local, path: "./my-plugin"}]
  )
  |> ClaudeCode.Stream.final_result()

%ResultMessage{result: text} = result
```

> **Tip:** You can also enable CLI-installed marketplace plugins directly via the `:plugins` option using the `name@marketplace` format (for example, `"code-simplifier@claude-plugins-official"`), or manage installations programmatically with `ClaudeCode.Plugin.install/2`.

## Complete example

Here is a full example demonstrating plugin loading and usage:

```elixir
alias ClaudeCode.Message.{SystemMessage, ResultMessage}

plugin_path = Path.join([__DIR__, "plugins", "my-plugin"])

{:ok, session} = ClaudeCode.start_link(
  plugins: [%{type: :local, path: plugin_path}],
  max_turns: 3
)

session
|> ClaudeCode.stream("What custom commands do you have available?")
|> Enum.each(fn
  %SystemMessage{subtype: :init, plugins: plugins, slash_commands: commands} ->
    IO.puts("Loaded plugins: #{inspect(plugins)}")
    IO.puts("Available commands: #{inspect(commands)}")

  %ResultMessage{result: text} ->
    IO.puts("Result: #{text}")

  _ ->
    :ok
end)
```

## Plugin structure reference

A plugin directory must contain a `.claude-plugin/plugin.json` manifest file. It can optionally include:

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          # Required: plugin manifest
├── commands/                 # Custom slash commands
│   └── custom-cmd.md
├── agents/                   # Custom agents
│   └── specialist.md
├── skills/                   # Agent Skills
│   └── my-skill/
│       └── SKILL.md
├── hooks/                    # Event handlers
│   └── hooks.json
├── .mcp.json                # MCP server definitions
└── .lsp.json                # LSP server configurations
```

> **Warning:** Do not put `commands/`, `agents/`, `skills/`, or `hooks/` inside the `.claude-plugin/` directory. Only `plugin.json` goes inside `.claude-plugin/`. All other directories must be at the plugin root level.

For detailed information on creating plugins, see:

- [Plugins](https://code.claude.com/docs/en/plugins) -- Complete plugin development guide
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference) -- Technical specifications and schemas

## Common use cases

### Development and testing

Load plugins during development without installing them globally:

```elixir
{:ok, session} = ClaudeCode.start_link(
  plugins: [%{type: :local, path: "./dev-plugins/my-plugin"}]
)
```

### Project-specific extensions

Include plugins in your project repository for team-wide consistency:

```elixir
{:ok, session} = ClaudeCode.start_link(
  plugins: [%{type: :local, path: "./project-plugins/team-workflows"}]
)
```

### Multiple plugin sources

Combine plugins from different locations:

```elixir
{:ok, session} = ClaudeCode.start_link(
  plugins: [
    %{type: :local, path: "./local-plugin"},
    %{type: :local, path: Path.expand("~/.claude/custom-plugins/shared-plugin")}
  ]
)
```

## Managing plugins

The `ClaudeCode.Plugin` module provides functions for managing plugin installations, wrapping the `claude plugin` CLI commands.

### Listing installed plugins

```elixir
{:ok, plugins} = ClaudeCode.Plugin.list()

Enum.each(plugins, fn plugin ->
  IO.puts("#{plugin.id} v#{plugin.version} (#{plugin.scope}, enabled: #{plugin.enabled})")
end)
```

### Installing and uninstalling

```elixir
# Install from a marketplace
{:ok, _} = ClaudeCode.Plugin.install("code-simplifier@claude-plugins-official")

# Install with a specific scope
{:ok, _} = ClaudeCode.Plugin.install("my-plugin@my-org", scope: :project)

# Uninstall
{:ok, _} = ClaudeCode.Plugin.uninstall("code-simplifier@claude-plugins-official")
```

### Enabling and disabling

```elixir
{:ok, _} = ClaudeCode.Plugin.enable("code-simplifier@claude-plugins-official")
{:ok, _} = ClaudeCode.Plugin.disable("code-simplifier@claude-plugins-official")

# Disable all plugins
{:ok, _} = ClaudeCode.Plugin.disable_all(scope: :project)
```

### Updating and validating

```elixir
# Update a plugin to the latest version
{:ok, _} = ClaudeCode.Plugin.update("code-simplifier@claude-plugins-official")

# Validate a local plugin manifest
{:ok, _} = ClaudeCode.Plugin.validate("./my-plugin")
```

## Managing marketplaces

The `ClaudeCode.Plugin.Marketplace` module provides functions for managing marketplace configurations.

### Listing marketplaces

```elixir
{:ok, marketplaces} = ClaudeCode.Plugin.Marketplace.list()

Enum.each(marketplaces, fn m ->
  IO.puts("#{m.name} (#{m.source}: #{m.repo})")
end)
```

### Adding and removing

```elixir
# Add from GitHub shorthand
{:ok, _} = ClaudeCode.Plugin.Marketplace.add("owner/repo")

# Add with scope and sparse checkout (for monorepos)
{:ok, _} = ClaudeCode.Plugin.Marketplace.add("owner/monorepo",
  scope: :project,
  sparse: [".claude-plugin", "plugins"]
)

# Remove a marketplace
{:ok, _} = ClaudeCode.Plugin.Marketplace.remove("my-marketplace")
```

### Updating

```elixir
# Update all marketplaces
{:ok, _} = ClaudeCode.Plugin.Marketplace.update()

# Update a specific marketplace
{:ok, _} = ClaudeCode.Plugin.Marketplace.update("my-marketplace")
```

## Troubleshooting

### Plugin not loading

If your plugin does not appear in the init message:

1. **Check the path** -- Ensure the path points to the plugin root directory (the one containing `.claude-plugin/`)
2. **Validate plugin.json** -- Ensure the manifest file has valid JSON syntax
3. **Check file permissions** -- Ensure the plugin directory and its contents are readable

### Commands not available

If plugin commands are not working:

1. **Use the namespace** -- Plugin commands require the `plugin-name:command-name` format
2. **Check the init message** -- Verify the command appears in `slash_commands` with the correct namespace prefix
3. **Validate command files** -- Ensure command markdown files are in the `commands/` directory within the plugin

### Path resolution issues

If relative paths do not resolve correctly:

1. **Check the working directory** -- Relative paths are resolved from the process working directory (or the `:cwd` option if set)
2. **Use absolute paths** -- For reliability, construct absolute paths with `Path.join/2` or `Path.expand/1`
3. **Normalize paths** -- Use `Path.expand/1` to resolve `~` and other path shortcuts

## See also

- [Plugins](https://code.claude.com/docs/en/plugins) -- Complete plugin development guide
- [Plugins reference](https://code.claude.com/docs/en/plugins-reference) -- Technical specifications
- [Slash Commands](slash-commands.md) -- Using slash commands in the SDK
- [Subagents](subagents.md) -- Working with specialized agents
- [Skills](skills.md) -- Using Agent Skills
