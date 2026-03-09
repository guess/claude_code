# Examples

Run these scripts from the repo root.

## Available scripts

- `examples/streaming_example.exs` - complete-message streaming helpers and raw-message handling
- `examples/character_streaming_example.exs` - partial-message streaming with `include_partial_messages: true`

## Default run command

If you use the SDK's default bundled CLI configuration, run:

```bash
mix run examples/streaming_example.exs
mix run examples/character_streaming_example.exs
```

## Using a system-installed Claude CLI

If you want the examples to use an external `claude` binary instead of the bundled one, set:

```elixir
# config/dev.exs
import Config

config :claude_code, cli_path: :global
```

Then run the same commands:

```bash
mix run examples/streaming_example.exs
mix run examples/character_streaming_example.exs
```

## One-off override without editing config

If you do not want to change `config/dev.exs`, require the example file from `-e` after setting `:cli_path`:

```bash
mix run -e 'Application.put_env(:claude_code, :cli_path, :global); Code.require_file("streaming_example.exs", "examples")'
mix run -e 'Application.put_env(:claude_code, :cli_path, :global); Code.require_file("character_streaming_example.exs", "examples")'
```

This form matters: `mix run -e '...' examples/foo.exs` only evaluates the expression and does not also run the script.

## Requirements

- Run from the repository root so the relative `examples` path resolves correctly.
- Ensure the external `claude` binary is on your `PATH` when using `cli_path: :global`.
- Authenticate the Claude CLI first with either `ANTHROPIC_API_KEY` or `claude /login`.
