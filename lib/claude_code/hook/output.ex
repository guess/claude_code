defmodule ClaudeCode.Hook.Output do
  @moduledoc """
  Top-level hook output struct returned to the CLI.

  Wraps common fields (`:continue`, `:decision`, `:stop_reason`, etc.) and an
  optional `:hook_specific_output` carrying event-specific data.

  Most hooks can use shorthand returns instead of building this struct directly:

      # These are equivalent:
      :ok
      %Output{}

      {:halt, stop_reason: "done"}
      %Output{continue: false, stop_reason: "done"}

      {:block, reason: "Rate limited"}
      %Output{decision: "block", reason: "Rate limited"}

  See `ClaudeCode.Hook` for the full shorthand reference.

  ## Fields

    * `:continue` - whether the agent should keep running (`false` to halt)
    * `:suppress_output` - suppress the hook's output from the conversation
    * `:stop_reason` - reason string when halting
    * `:decision` - `"block"` to block a user prompt submission
    * `:system_message` - system message to inject into the conversation
    * `:reason` - human-readable reason for the decision
    * `:hook_specific_output` - event-specific output struct (e.g. `PreToolUse`, `PostToolUse`)
  """

  alias ClaudeCode.Hook.Output
  alias ClaudeCode.Hook.PermissionDecision
  alias Output.Async
  alias Output.Notification
  alias Output.PermissionRequest
  alias Output.PostToolUse
  alias Output.PostToolUseFailure
  alias Output.PreCompact
  alias Output.PreToolUse
  alias Output.SessionStart
  alias Output.SubagentStart
  alias Output.UserPromptSubmit

  @type decision :: String.t()

  @type hook_specific_output ::
          Output.PreToolUse.t()
          | Output.PostToolUse.t()
          | Output.PostToolUseFailure.t()
          | Output.UserPromptSubmit.t()
          | Output.SessionStart.t()
          | Output.Notification.t()
          | Output.SubagentStart.t()
          | Output.PreCompact.t()
          | Output.PermissionRequest.t()

  @type t :: %__MODULE__{
          continue: boolean() | nil,
          suppress_output: boolean() | nil,
          stop_reason: String.t() | nil,
          decision: decision() | nil,
          system_message: String.t() | nil,
          reason: String.t() | nil,
          hook_specific_output: hook_specific_output() | nil
        }

  defstruct [
    :continue,
    :suppress_output,
    :stop_reason,
    :decision,
    :system_message,
    :reason,
    :hook_specific_output
  ]

  # -- Main to_wire dispatcher --

  @spec to_wire(struct()) :: map()
  def to_wire(%Async{} = output), do: Async.to_wire(output)

  def to_wire(%__MODULE__{} = output) do
    base =
      %{}
      |> maybe_put("continue", output.continue)
      |> maybe_put("suppressOutput", output.suppress_output)
      |> maybe_put("stopReason", output.stop_reason)
      |> maybe_put("decision", output.decision)
      |> maybe_put("systemMessage", output.system_message)
      |> maybe_put("reason", output.reason)

    case output.hook_specific_output do
      nil -> base
      inner -> Map.put(base, "hookSpecificOutput", inner.__struct__.to_wire(inner))
    end
  end

  def to_wire(%PermissionDecision.Allow{} = d), do: PermissionDecision.Allow.to_wire(d)
  def to_wire(%PermissionDecision.Deny{} = d), do: PermissionDecision.Deny.to_wire(d)

  # -- Shared helper --

  @doc false
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  # -- Shorthand coercion --

  @doc false
  @spec coerce(term(), String.t() | atom()) :: struct()

  # Tier 1: bare atoms
  def coerce(:ok, :can_use_tool), do: %PermissionDecision.Allow{}
  def coerce(:ok, _event), do: %__MODULE__{}
  def coerce(:allow, event), do: coerce({:allow, []}, event)
  def coerce(:deny, event), do: coerce({:deny, []}, event)

  # Tier 3: struct passthrough
  def coerce(%__MODULE__{} = output, _event), do: output
  def coerce(%Async{} = output, _event), do: output
  def coerce(%PermissionDecision.Allow{} = output, _event), do: output
  def coerce(%PermissionDecision.Deny{} = output, _event), do: output

  # Tier 2: tagged tuples — top-level Output fields

  # :halt — Stop / SubagentStop → continue: false
  def coerce({:halt, opts}, _event) do
    struct(__MODULE__, [{:continue, false} | opts])
  end

  # :block — UserPromptSubmit → decision: "block"
  def coerce({:block, opts}, _event) do
    struct(__MODULE__, [{:decision, "block"} | opts])
  end

  # Tier 2: tagged tuples — hook-specific Output fields

  # :allow / :deny / :ask — PreToolUse
  def coerce({action, opts}, "PreToolUse") when action in [:allow, :deny, :ask] do
    wrap(struct(PreToolUse, [{:permission_decision, to_string(action)} | opts]))
  end

  # :allow / :deny — PermissionRequest
  def coerce({:allow, opts}, "PermissionRequest") do
    wrap(%PermissionRequest{decision: struct(PermissionDecision.Allow, opts)})
  end

  def coerce({:deny, opts}, "PermissionRequest") do
    wrap(%PermissionRequest{decision: struct(PermissionDecision.Deny, opts)})
  end

  # :allow / :deny — can_use_tool
  def coerce({:allow, opts}, :can_use_tool), do: struct(PermissionDecision.Allow, opts)
  def coerce({:deny, opts}, :can_use_tool), do: struct(PermissionDecision.Deny, opts)

  # {:ok, opts} — event-specific inner struct
  def coerce({:ok, opts}, "PreToolUse"), do: wrap(struct(PreToolUse, opts))
  def coerce({:ok, opts}, "PostToolUse"), do: wrap(struct(PostToolUse, opts))
  def coerce({:ok, opts}, "PostToolUseFailure"), do: wrap(struct(PostToolUseFailure, opts))
  def coerce({:ok, opts}, "UserPromptSubmit"), do: wrap(struct(UserPromptSubmit, opts))
  def coerce({:ok, opts}, "SessionStart"), do: wrap(struct(SessionStart, opts))
  def coerce({:ok, opts}, "Notification"), do: wrap(struct(Notification, opts))
  def coerce({:ok, opts}, "SubagentStart"), do: wrap(struct(SubagentStart, opts))
  def coerce({:ok, opts}, "PreCompact"), do: wrap(struct(PreCompact, opts))
  def coerce({:ok, _opts}, _event), do: %__MODULE__{}

  # Catch-all: unrecognized values (e.g. legacy bare atoms) → empty output
  def coerce(_value, _event), do: %__MODULE__{}

  defp wrap(inner), do: %__MODULE__{hook_specific_output: inner}
end
