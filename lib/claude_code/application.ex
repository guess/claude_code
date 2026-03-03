defmodule ClaudeCode.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ClaudeCode.ParseWarning, []}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: ClaudeCode.InternalSupervisor
    )
  end
end
