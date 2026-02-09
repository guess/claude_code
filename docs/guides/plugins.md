# Plugins

> **📚 Official Documentation:** This guide is based on the [official Claude Agent SDK documentation](https://platform.claude.com/docs/en/agent-sdk/plugins). Examples are adapted for Elixir.

Plugins extend Claude Code with additional capabilities. They can be loaded from local directories.

## Loading Plugins

Use the `plugins` option to load local plugins:

```elixir
# As paths
{:ok, session} = ClaudeCode.start_link(
  plugins: ["./my-plugin", "./another-plugin"]
)

# As typed configurations
{:ok, session} = ClaudeCode.start_link(
  plugins: [
    %{type: :local, path: "./my-plugin"},
    %{type: :local, path: "./another-plugin"}
  ]
)
```

Each plugin path is passed to the CLI via `--plugin-dir`.

## Detecting Loaded Plugins

The `SystemMessage` lists loaded plugins:

```elixir
session
|> ClaudeCode.stream("Hello")
|> Enum.each(fn
  %ClaudeCode.Message.SystemMessage{plugins: plugins} ->
    Enum.each(plugins, fn
      %{name: name, path: path} -> IO.puts("Plugin: #{name} (#{path})")
      name when is_binary(name) -> IO.puts("Plugin: #{name}")
    end)
  _ -> :ok
end)
```

## Next Steps

- [MCP](mcp.md) - Extend Claude with MCP tools
- [Custom Tools](custom-tools.md) - Build tools with Hermes
- [Skills](skills.md) - Project-level skills
