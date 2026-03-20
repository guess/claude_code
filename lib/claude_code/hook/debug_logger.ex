defmodule ClaudeCode.Hook.DebugLogger do
  @moduledoc false

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
    @moduledoc false

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
