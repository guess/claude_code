import Config

# Use a nonexistent path by default in tests to prevent accidental CLI usage.
# Tests that need a real/mock CLI should override with cli_path option.
config :claude_code,
  cli_path: "/nonexistent/test/claude"
