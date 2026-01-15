# Check CLI Options

Compare `claude --help` output against our Options module to identify missing or outdated CLI flag support.

## Steps

1. Run the CLI help command:
```bash
claude --help
```

2. Read our options implementation:
- `lib/claude_code/options.ex`

3. Compare and report:
- **New CLI flags**: Flags in `--help` that we don't have in `@session_opts_schema` or `convert_option_to_cli_flag/2`
- **Deprecated flags**: Options we support that are no longer in `--help`
- **Naming mismatches**: Flags where our option name doesn't match the CLI flag pattern

4. For each new flag found, suggest:
- The `:snake_case_atom` option name for the schema
- The NimbleOptions type definition
- The `convert_option_to_cli_flag/2` clause

## Notes

- `--verbose` is already enabled by default by the SDK (passed in CLI.ex), so it's not exposed as an option
