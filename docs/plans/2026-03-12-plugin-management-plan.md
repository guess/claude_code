# Plugin Management Implementation Plan

Design: `docs/plans/2026-03-12-plugin-management-design.md`

## Step 1: Plugin.Marketplace struct and CLI wrapper

**Files:**
- `lib/claude_code/plugin/marketplace.ex` — struct + `list/1`, `add/2`, `remove/1`, `update/1`
- `test/claude_code/plugin/marketplace_test.exs` — tests

Start here because `Plugin` depends on marketplace concepts. Functions resolve the CLI binary via `ClaudeCode.CLI`, run `System.cmd/3`, parse JSON output into structs.

**Verify:** `mix test test/claude_code/plugin/marketplace_test.exs`

## Step 2: Plugin struct and CLI wrapper

**Files:**
- `lib/claude_code/plugin.ex` — struct + `list/1`, `install/2`, `uninstall/2`, `enable/2`, `disable/2`, `disable_all/1`, `update/2`, `validate/1`
- `test/claude_code/plugin_test.exs` — tests

Same pattern as Marketplace — resolve CLI, run command, parse output.

**Verify:** `mix test test/claude_code/plugin_test.exs`

## Step 3: Marketplace plugin type in Options

**Files:**
- `lib/claude_code/options.ex` — update `:plugins` doc to mention marketplace type
- `test/claude_code/options_test.exs` — add validation tests for marketplace plugin maps and `@` strings

**Verify:** `mix test test/claude_code/options_test.exs`

## Step 4: Preprocess marketplace plugins in CLI.Command

**Files:**
- `lib/claude_code/cli/command.ex` — add `preprocess_plugins/1`, update `convert_option(:plugins, ...)` to only handle locals (marketplace already extracted)
- `test/claude_code/cli/command_test.exs` — tests for marketplace → settings merge, local passthrough, mixed lists, settings merge with existing enabledPlugins

**Verify:** `mix test test/claude_code/cli/command_test.exs`

## Step 5: Update documentation

**Files:**
- `docs/guides/plugins.md` — Add sections for marketplace plugins (loading by ID, `@` shorthand), plugin management API (`ClaudeCode.Plugin` functions), and marketplace management (`ClaudeCode.Plugin.Marketplace` functions). Update existing examples to show mixed local + marketplace usage.
- `CLAUDE.md` — Add `Plugin` and `Plugin.Marketplace` to the architecture/key modules section and file structure

**Verify:** Review docs for accuracy against implementation

## Step 6: Full quality check

**Verify:** `mix quality && mix test`
