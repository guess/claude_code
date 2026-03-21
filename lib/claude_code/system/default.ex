defmodule ClaudeCode.System.Default do
  @moduledoc false
  @behaviour ClaudeCode.System

  @impl true
  def cmd(command, args, opts) do
    System.cmd(command, args, opts)
  end

  @impl true
  def find_executable(name) do
    System.find_executable(name)
  end
end
