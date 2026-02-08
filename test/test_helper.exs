ExUnit.start(capture_log: true)

# Start the ownership server for ClaudeCode.Test
Supervisor.start_link([ClaudeCode.Test], strategy: :one_for_one)
