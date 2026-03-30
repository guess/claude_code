---
paths:
  - "lib/claude_code/options.ex"
---

When adding, editing, or removing options from the session schema, update the corresponding `convert_option` clause in `lib/claude_code/cli/command.ex`. Options that are not CLI flags need a `defp convert_option(:option_name, _value), do: nil` clause to prevent them from leaking to the CLI.
