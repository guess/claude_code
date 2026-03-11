defmodule ClaudeCode.Hook do
  @moduledoc """
  Behaviour for hook callbacks.

  Implement this behaviour in a module, or pass an anonymous function
  with the same `call/2` signature. Used by the `:hooks` option.

  ## Hook events and return types

  The return type depends on which event the hook is registered for.
  All hook inputs include common fields (`:hook_event_name`, `:session_id`,
  `:transcript_path`, `:cwd`, `:permission_mode`, and optional `:agent_id`/`:agent_type`).

  See the [Hooks guide](hooks.html#hook-event-reference) for the full input
  field reference per event.

  ### PreToolUse (permission decisions)

  Input: `:tool_name`, `:tool_input`, `:tool_use_id`

      :allow
      {:allow, updated_input}
      {:deny, reason}

  ### PostToolUse (observation)

  Input: `:tool_name`, `:tool_input`, `:tool_response`, `:tool_use_id`

      :ok

  ### PostToolUseFailure (observation)

  Input: `:tool_name`, `:tool_input`, `:tool_use_id`, `:error`, `:is_interrupt`

      :ok

  ### UserPromptSubmit

  Input: `:prompt`

      :ok
      {:reject, reason}

  ### Stop

  Input: `:stop_hook_active`, `:last_assistant_message`

      :ok
      {:continue, reason}

  ### SubagentStart (observation)

  Input: `:agent_id`, `:agent_type`

      :ok

  ### SubagentStop

  Input: `:stop_hook_active`, `:agent_id`, `:agent_type`,
  `:agent_transcript_path`, `:last_assistant_message`

      :ok
      {:continue, reason}

  ### PreCompact

  Input: `:trigger`, `:custom_instructions`

      :ok
      {:instructions, custom_instructions}

  ### Notification (observation)

  Input: `:message`, `:notification_type`, `:title`

      :ok

  ### PermissionRequest (permission decisions)

  Input: `:tool_name`, `:tool_input`, `:permission_suggestions`

      :allow
      {:allow, updated_input}
      {:deny, reason}
  """

  @callback call(input :: map(), tool_use_id :: String.t() | nil) :: term()

  @doc """
  Invokes a hook callback (module or function) with error protection.

  Returns the callback's result, or `{:error, reason}` if it raises.
  """
  @spec invoke(module() | function(), map(), String.t() | nil) :: term()
  def invoke(hook, input, tool_use_id) when is_atom(hook) do
    hook.call(input, tool_use_id)
  rescue
    e -> {:error, Exception.message(e)}
  end

  def invoke(hook, input, tool_use_id) when is_function(hook, 2) do
    hook.(input, tool_use_id)
  rescue
    e -> {:error, Exception.message(e)}
  end
end
