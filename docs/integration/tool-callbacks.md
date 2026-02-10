# Tool Callbacks

Tool callbacks allow you to monitor, log, and audit all tool executions during a ClaudeCode session. The callback is invoked asynchronously after each tool completes.

## Basic Usage

```elixir
callback = fn event ->
  IO.puts("Tool: #{event.name}, Success: #{not event.is_error}")
end

{:ok, session} = ClaudeCode.start_link(tool_callback: callback)
```

## Callback Event Structure

The callback receives an event map with:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Tool name (e.g., "View", "Edit", "Bash") |
| `tool_use_id` | string | Unique identifier for this tool invocation |
| `input` | map | Input parameters passed to the tool |
| `result` | string | Tool output (may be nil) |
| `is_error` | boolean | Whether the tool execution failed |
| `timestamp` | DateTime | When the tool was executed |

## Logging

```elixir
require Logger

callback = fn event ->
  Logger.info("Tool executed",
    tool: event.name,
    input: event.input,
    success: not event.is_error,
    timestamp: event.timestamp
  )
end

{:ok, session} = ClaudeCode.start_link(tool_callback: callback)
```

## Telemetry Integration

Emit telemetry events for metrics and monitoring:

```elixir
callback = fn event ->
  :telemetry.execute(
    [:claude_code, :tool, :executed],
    %{duration_ms: 0},
    %{
      tool_name: event.name,
      tool_use_id: event.tool_use_id,
      is_error: event.is_error,
      input_keys: Map.keys(event.input),
      result_length: String.length(event.result || "")
    }
  )
end

{:ok, session} = ClaudeCode.start_link(tool_callback: callback)

# Attach a handler
:telemetry.attach(
  "tool-logger",
  [:claude_code, :tool, :executed],
  fn _event, _measurements, metadata, _config ->
    IO.puts("Tool #{metadata.tool_name} executed")
  end,
  nil
)
```

## Security Monitoring

Monitor for sensitive operations:

```elixir
@sensitive_tools ["Edit", "Write", "Bash"]
@sensitive_paths ["/etc", "/usr", "~/.ssh"]

callback = fn event ->
  if sensitive_operation?(event) do
    alert_security_team(event)
  end
end

defp sensitive_operation?(event) do
  event.name in @sensitive_tools and
    path_is_sensitive?(event.input["path"] || event.input["file_path"])
end

defp path_is_sensitive?(nil), do: false
defp path_is_sensitive?(path) do
  Enum.any?(@sensitive_paths, &String.starts_with?(path, &1))
end

defp alert_security_team(event) do
  Logger.warning("Sensitive operation",
    tool: event.name,
    input: event.input
  )
end
```

## Analytics Dashboard

Track tool usage statistics:

```elixir
defmodule ToolAnalytics do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_stats, do: GenServer.call(__MODULE__, :get_stats)

  def callback(event) do
    GenServer.cast(__MODULE__, {:record, event})
  end

  def init(_opts) do
    {:ok, %{tool_counts: %{}, error_counts: %{}, total: 0}}
  end

  def handle_cast({:record, event}, state) do
    new_state = state
    |> Map.update!(:total, &(&1 + 1))
    |> update_in([:tool_counts, event.name], &((&1 || 0) + 1))
    |> then(fn s ->
      if event.is_error do
        update_in(s, [:error_counts, event.name], &((&1 || 0) + 1))
      else
        s
      end
    end)

    {:noreply, new_state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end
end

# Usage
{:ok, _} = ToolAnalytics.start_link()
{:ok, session} = ClaudeCode.start_link(tool_callback: &ToolAnalytics.callback/1)

# Later
ToolAnalytics.get_stats()
# => %{total: 15, tool_counts: %{"View" => 10, "Edit" => 5}, error_counts: %{}}
```

## Audit Trail

Store tool executions for compliance:

```elixir
defmodule AuditLog do
  def callback(event) do
    audit_entry = %{
      tool: event.name,
      tool_use_id: event.tool_use_id,
      input: event.input,
      result_preview: String.slice(event.result || "", 0, 100),
      is_error: event.is_error,
      timestamp: event.timestamp
    }

    # Store in database, send to logging service, etc.
    MyApp.AuditRepo.insert!(audit_entry)
  end
end

{:ok, session} = ClaudeCode.start_link(tool_callback: &AuditLog.callback/1)
```

## Combining Multiple Callbacks

```elixir
defmodule CombinedCallbacks do
  def callback(event) do
    log_event(event)
    emit_telemetry(event)
    check_security(event)
  end

  defp log_event(event), do: Logger.info("Tool: #{event.name}")
  defp emit_telemetry(event), do: :telemetry.execute([:tool], %{}, %{name: event.name})
  defp check_security(event), do: SecurityMonitor.check(event)
end
```

## Next Steps

- [Permissions Guide](../guides/permissions.md) - Control tool access
- [Hosting](../guides/hosting.md) - Production patterns
