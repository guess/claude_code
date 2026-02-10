defmodule ClaudeCode.SystemCmd.Default do
  @moduledoc false
  @behaviour ClaudeCode.SystemCmd

  @impl true
  def cmd(command, args, opts) do
    System.cmd(command, args, opts)
  end
end
