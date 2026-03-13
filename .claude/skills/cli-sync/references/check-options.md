# Check Options

Self-contained instructions for a parallel agent that checks CLI options/flags coverage across the CLI, TypeScript SDK, Python SDK, and the Elixir Options module.

## Purpose

Detect new, removed, or changed CLI flags and SDK options by comparing CLI help output and SDK type definitions against the Elixir Options module. Cross-reference all three upstream sources to find coverage gaps in the Elixir SDK's option handling.

## Files to Read

### Captured data

- `captured/cli-help.txt` -- CLI `--help` output listing all available flags.
- `captured/ts-sdk-types.d.ts` -- Search for the `ClaudeAgentOptions` or `Options` type definition. Extract all option names and their types.
- `captured/python-sdk-subprocess-cli.py` -- The `_build_command()` method showing how the Python SDK maps options to CLI flags.
- `captured/python-sdk-types.py` -- Python SDK's options type definitions (class fields and their types).
- `captured/python-sdk-client.py` -- Internal client showing option validation, mutual exclusion rules (e.g., `can_use_tool` vs `permission_prompt_tool_name`), and agent/hook preprocessing.

### Elixir implementation

- `lib/claude_code/options.ex` -- `@session_opts_schema` and `@query_opts_schema` define all user-configurable options with NimbleOptions validation.
- `lib/claude_code/cli/command.ex` -- `convert_option_to_cli_flag/2` clauses map Elixir options to CLI flag strings.

### Current tracking

- `references/cli-flags.md` -- documents all currently implemented flag mappings, always-enabled flags, Elixir-only options, and patterns for adding new flags. Use as a baseline to identify what is already tracked vs newly discovered.

## Analysis Steps

### 1. Extract CLI flags

Read `cli-help.txt` and extract every `--flag-name` entry. Build a list of all CLI flags with their descriptions and value types (boolean, string, list, etc.).

### 2. Extract TS SDK options

Locate the options/agent-options type definition in `ts-sdk-types.d.ts` (look for `ClaudeAgentOptions`, `Options`, or similar interface). List every property name and its TypeScript type.

### 3. Extract Python SDK flag mappings

Read `python-sdk-subprocess-cli.py` and find the `_build_command` method (or equivalent). Extract each option-to-flag mapping: the Python option name, the CLI flag it maps to, and how the value is formatted (boolean presence, string value, comma-separated list, repeated flag, JSON-encoded, etc.).

Also read `python-sdk-types.py` to confirm option names and types from the Python SDK's type definitions.

### 4. Extract Elixir schema keys

Read `options.ex` and extract all keys from `@session_opts_schema` and `@query_opts_schema`. Note each key's NimbleOptions type and documentation.

### 5. Extract Elixir flag conversion clauses

Read `command.ex` and list all `convert_option_to_cli_flag/2` clause heads. Each clause maps an Elixir option atom to one or more CLI flags. Note the conversion pattern (boolean, value, list-CSV, list-repeated, JSON-encoded).

### 6. Cross-reference all sources

Build a unified table by matching across all four sources (CLI help, TS SDK, Python SDK, Elixir SDK). For each flag or option found in any source, determine:

- Whether it appears in CLI `--help`
- The corresponding TS SDK option name (if any)
- The corresponding Python SDK option name (if any)
- The corresponding Elixir option key (if any)
- Whether a `convert_option_to_cli_flag/2` clause exists

Flag any of the following:

- **New CLI flags** -- Present in `--help` but absent from `@session_opts_schema` and not in the ignore lists below.
- **New SDK options** -- Present in TS or Python SDK types but absent from `@session_opts_schema`.
- **Deprecated flags** -- Present in the Elixir schema or flag conversion clauses but absent from current `--help` output.
- **Missing conversion** -- Present in `@session_opts_schema` but no matching `convert_option_to_cli_flag/2` clause (option is accepted but never sent to CLI).
- **SDK-only options** -- Present in TS or Python SDK but not in CLI `--help` (SDK-specific abstractions).

## Ignore Lists

### SDK-internal flags

Always enabled by the SDK, not user-configurable. Skip these during comparison:

- `--verbose`
- `--output-format`
- `--input-format`
- `--print`

### CLI-only flags

Interactive-only flags not useful for a subprocess SDK. Skip these:

- `--chrome`, `--no-chrome`
- `--ide`
- `--tmux`

## Output Format

Return a flags coverage table:

| CLI Flag | TS SDK Option | Python SDK Option | Elixir Option | Status |
|---|---|---|---|---|

Status values:

- **Implemented** -- Flag exists in Elixir schema with a working `convert_option_to_cli_flag/2` clause.
- **Missing** -- Flag exists in CLI help or upstream SDK but not in the Elixir schema.
- **Deprecated** -- Flag exists in the Elixir schema but no longer appears in CLI help.
- **SDK-internal** -- Always enabled by the SDK; not user-configurable.
- **CLI-only** -- Interactive-only; not applicable to subprocess usage.
- **No conversion** -- In the Elixir schema but missing a `convert_option_to_cli_flag/2` clause.
- **Elixir-only** -- Elixir SDK option that does not map to a CLI flag (e.g., `:name`, `:timeout`, `:adapter`).

Also report summary counts:

- Total user-facing CLI flags (excluding SDK-internal and CLI-only)
- Number implemented in Elixir
- Number missing from Elixir
- Number deprecated
- Any flags that appear in TS or Python SDK but not in CLI help (SDK-specific options)
