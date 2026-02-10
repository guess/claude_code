# ExUnit.start(capture_log: true)
ExUnit.start()

# Start the ownership server for ClaudeCode.Test
Supervisor.start_link([ClaudeCode.Test], strategy: :one_for_one)

# Define Mox mocks
Mox.defmock(ClaudeCode.SystemCmd.Mock, for: ClaudeCode.SystemCmd)
