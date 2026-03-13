defmodule ClaudeCode.Hook do
  @moduledoc """
  Behaviour for hook callbacks.

  Implement this behaviour in a module, or pass an anonymous function
  with the same `call/2` signature. Used by the `:hooks` option.

  See the [Hooks guide](hooks.html) for configuration, matchers, patterns,
  and troubleshooting.

  ## Output structs

  All hook callbacks should return ClaudeCode.Hook.Output structs.
  Use `alias ClaudeCode.Hook.Output` in your hook modules for concise notation.

  ## Common input fields

  All hook events include these base fields:

  | Field | Type | Description |
  |-------|------|-------------|
  | `:hook_event_name` | `String.t()` | The hook type (`"PreToolUse"`, `"PostToolUse"`, etc.) |
  | `:session_id` | `String.t()` | Current session identifier |
  | `:transcript_path` | `String.t()` | Path to the conversation transcript |
  | `:cwd` | `String.t()` | Current working directory |
  | `:permission_mode` | `String.t()` | Permission mode (e.g., `"default"`, `"acceptEdits"`, `"bypassPermissions"`) |
  | `:agent_id` | `String.t()` | Subagent identifier. Present only within a subagent; absent on the main thread. |
  | `:agent_type` | `String.t()` | Agent type name (e.g., `"general-purpose"`, `"code-reviewer"`). Present within subagents, or on the main thread when started with `--agent`. |

  > **Key normalization:** Hook input fields are converted to atom keys. All documented
  > fields are guaranteed to be atoms. Unknown or future fields fall back to
  > `String.to_existing_atom/1` — if the atom doesn't already exist at runtime, the key
  > is preserved as a string, avoiding unbounded atom creation.

  ## Hook event reference

  ### PreToolUse

  Fires before a tool executes. Can block, allow, or modify the tool call.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:tool_name` | `String.t()` | Name of the tool being called |
  | `:tool_input` | `map` | Arguments passed to the tool (keys are strings) |
  | `:tool_use_id` | `String.t()` | Unique identifier for this tool call |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | No opinion — continue through permission pipeline |
  | `%Output{hook_specific_output: %Output.PreToolUse{permission_decision: "allow"}}` | Bypass permission system |
  | `%Output{hook_specific_output: %Output.PreToolUse{permission_decision: "allow", updated_input: %{...}}}` | Allow with modified input |
  | `%Output{hook_specific_output: %Output.PreToolUse{permission_decision: "allow", permission_decision_reason: "...", additional_context: "..."}}` | Allow with context |
  | `%Output{hook_specific_output: %Output.PreToolUse{permission_decision: "deny", permission_decision_reason: "..."}}` | Block tool call |
  | `%Output{hook_specific_output: %Output.PreToolUse{permission_decision: "ask", permission_decision_reason: "..."}}` | Escalate to user prompt |

  **Example:**

      defmodule MyApp.BlockDangerous do
        @behaviour ClaudeCode.Hook
        alias ClaudeCode.Hook.Output

        @impl true
        def call(%{hook_event_name: "PreToolUse", tool_input: %{"command" => cmd}}, _tool_use_id) do
          if String.contains?(cmd, "rm -rf /") do
            %Output{
              hook_specific_output: %Output.PreToolUse{
                permission_decision: "deny",
                permission_decision_reason: "Dangerous command blocked"
              }
            }
          else
            %Output{
              hook_specific_output: %Output.PreToolUse{permission_decision: "allow"}
            }
          end
        end

        def call(_input, _tool_use_id), do: %Output{}
      end

  ### PostToolUse

  Fires after a tool executes successfully. Observation only.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:tool_name` | `String.t()` | Name of the tool that was called |
  | `:tool_input` | `map` | Arguments that were passed to the tool |
  | `:tool_response` | `any` | Result returned from tool execution |
  | `:tool_use_id` | `String.t()` | Unique identifier for this tool call |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Acknowledge the event |

  **Example:**

      defmodule MyApp.AuditLogger do
        @behaviour ClaudeCode.Hook
        alias ClaudeCode.Hook.Output

        @impl true
        def call(%{hook_event_name: "PostToolUse"} = event, _tool_use_id) do
          MyApp.AuditLog.insert(%{
            tool: event.tool_name,
            input: event.tool_input,
            result: event.tool_response
          })
          %Output{}
        end

        def call(_input, _tool_use_id), do: %Output{}
      end

  ### PostToolUseFailure

  Fires after a tool execution fails. Observation only.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:tool_name` | `String.t()` | Name of the tool that failed |
  | `:tool_input` | `map` | Arguments that were passed to the tool |
  | `:tool_use_id` | `String.t()` | Unique identifier for this tool call |
  | `:error` | `String.t()` | Error message from the failure |
  | `:is_interrupt` | `boolean` | Whether the failure was caused by an interrupt |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Acknowledge the event |

  ### UserPromptSubmit

  Fires when a user submits a prompt. Can block the submission.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:prompt` | `String.t()` | The user's prompt text |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Allow the prompt |
  | `%Output{decision: "block", reason: "..."}` | Block the prompt submission |

  ### Stop

  Fires when the agent is about to stop. Can keep the session running.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:stop_hook_active` | `boolean` | Whether a stop hook is currently processing |
  | `:last_assistant_message` | `String.t()` | Text content of the last assistant message before stopping |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Allow the session to stop |
  | `%Output{continue: false, stop_reason: "..."}` | Keep the session running |

  **Example:**

      defmodule MyApp.BudgetGuard do
        @behaviour ClaudeCode.Hook
        alias ClaudeCode.Hook.Output

        @impl true
        def call(%{hook_event_name: "Stop"}, _tool_use_id) do
          if MyApp.Budget.remaining() > 0 do
            %Output{continue: false, stop_reason: "Budget remaining, keep working"}
          else
            %Output{}
          end
        end

        def call(_input, _tool_use_id), do: %Output{}
      end

  ### SubagentStart

  Fires when a subagent is initialized. Observation only.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:agent_id` | `String.t()` | Unique identifier for the subagent |
  | `:agent_type` | `String.t()` | Type/role of the subagent |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Acknowledge the event |

  ### SubagentStop

  Fires when a subagent completes. Can keep the subagent running.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:stop_hook_active` | `boolean` | Whether a stop hook is currently processing |
  | `:agent_id` | `String.t()` | Unique identifier for the subagent |
  | `:agent_transcript_path` | `String.t()` | Path to the subagent's conversation transcript |
  | `:agent_type` | `String.t()` | Type/role of the subagent |
  | `:last_assistant_message` | `String.t()` | Text content of the last assistant message before stopping |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Allow the subagent to stop |
  | `%Output{continue: false, stop_reason: "..."}` | Keep the subagent running |

  ### PreCompact

  Fires before conversation compaction. Can provide custom instructions.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:trigger` | `String.t()` | What triggered compaction: `"manual"` or `"auto"` |
  | `:custom_instructions` | `String.t() \\| nil` | Custom instructions already provided for compaction |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Allow compaction normally |
  | `%Output{hook_specific_output: %Output.PreCompact{custom_instructions: "..."}}` | Provide custom instructions for compaction |

  ### Notification

  Fires when the agent sends status messages. Observation only.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:message` | `String.t()` | Status message from the agent |
  | `:notification_type` | `String.t()` | Type of notification: `"permission_prompt"`, `"idle_prompt"`, `"auth_success"`, or `"elicitation_dialog"` |
  | `:title` | `String.t()` | Optional title set by the agent |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | Acknowledge the event |

  ### PermissionRequest

  Fires when a tool requires permission. Similar to `PreToolUse` but occurs at the
  permission prompt stage rather than the hook stage.

  **Input fields** (in addition to common fields):

  | Field | Type | Description |
  |-------|------|-------------|
  | `:tool_name` | `String.t()` | Name of the tool requesting permission |
  | `:tool_input` | `map` | Arguments passed to the tool |
  | `:permission_suggestions` | `list` | Suggested permission updates to avoid future prompts |

  **Return values:**

  | Return | Effect |
  |--------|--------|
  | `%Output{}` | No opinion |
  | `%Output{hook_specific_output: %Output.PermissionRequest{decision: %Output.PermissionDecision.Allow{}}}` | Grant permission |
  | `%Output{hook_specific_output: %Output.PermissionRequest{decision: %Output.PermissionDecision.Allow{updated_input: %{...}}}}` | Grant with modified input |
  | `%Output{hook_specific_output: %Output.PermissionRequest{decision: %Output.PermissionDecision.Allow{updated_permissions: [...]}}}` | Grant with permission updates |
  | `%Output{hook_specific_output: %Output.PermissionRequest{decision: %Output.PermissionDecision.Deny{message: "..."}}}` | Deny permission |
  | `%Output{hook_specific_output: %Output.PermissionRequest{decision: %Output.PermissionDecision.Deny{message: "...", interrupt: true}}}` | Deny and interrupt |
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
