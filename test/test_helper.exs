# Compile support files
Code.compile_file("test/support/message_fixtures.exs")

ExUnit.start()

# Start the ownership server for ClaudeCode.Test
Supervisor.start_link([ClaudeCode.Test], strategy: :one_for_one)
