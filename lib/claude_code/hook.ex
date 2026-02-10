defmodule ClaudeCode.Hook do
  @moduledoc """
  Behaviour for hook callbacks.

  Implement this behaviour in a module, or pass an anonymous function
  with the same `call/2` signature. Used by both `:can_use_tool` and
  `:hooks` options.

  ## Return types by event

  The return type depends on which event the hook is registered for:

  ### can_use_tool / PreToolUse (permission decisions)

      :allow
      {:allow, updated_input}
      {:allow, updated_input, permissions: [permission_update]}
      {:deny, reason}
      {:deny, reason, interrupt: true}

  ### PostToolUse / PostToolUseFailure (observation only)

      :ok

  ### UserPromptSubmit

      :ok
      {:reject, reason}

  ### Stop / SubagentStop

      :ok
      {:continue, reason}

  ### PreCompact

      :ok
      {:instructions, custom_instructions}

  ### Notification / SubagentStart (observation only)

      :ok
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
