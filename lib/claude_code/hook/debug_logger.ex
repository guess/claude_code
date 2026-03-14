defmodule ClaudeCode.Hook.DebugLogger do
  @moduledoc """
  A diagnostic hook that logs every invocation with event name, tool name,
  and available input keys. Returns `:ok` so it never interferes with
  normal execution.

  ## Usage

  Register it for any event types you want to observe:

      {:ok, session} = ClaudeCode.start_link(
        hooks: %{
          PreToolUse: [ClaudeCode.Hook.DebugLogger],
          PostToolUse: [ClaudeCode.Hook.DebugLogger],
          Stop: [ClaudeCode.Hook.DebugLogger]
        }
      )

  For `can_use_tool`, use `ClaudeCode.Hook.DebugLogger.Permissive` which
  returns `:allow` instead of `:ok`:

      {:ok, session} = ClaudeCode.start_link(
        can_use_tool: ClaudeCode.Hook.DebugLogger.Permissive
      )
  """

  @behaviour ClaudeCode.Hook

  require Logger

  @impl true
  def call(input, tool_use_id) do
    event = input[:hook_event_name] || "unknown"
    tool = input[:tool_name] || "n/a"

    Logger.info(
      "[DebugLogger] event=#{event} tool=#{tool} tool_use_id=#{inspect(tool_use_id)} keys=#{inspect(Map.keys(input))}"
    )

    :ok
  end

  defmodule Permissive do
    @moduledoc """
    Like `ClaudeCode.Hook.DebugLogger` but returns `:allow` — suitable for
    `can_use_tool` callbacks.
    """

    @behaviour ClaudeCode.Hook

    require Logger

    @impl true
    def call(input, tool_use_id) do
      Logger.info(
        "[DebugLogger] event=can_use_tool tool=#{input[:tool_name]} tool_use_id=#{inspect(tool_use_id)} keys=#{inspect(Map.keys(input))}"
      )

      {:allow, []}
    end
  end
end
