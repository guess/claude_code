defmodule ClaudeCode.Hook.Output do
  @moduledoc false

  alias ClaudeCode.Hook.Output

  @type t :: %__MODULE__{}

  defstruct [
    :continue,
    :suppress_output,
    :stop_reason,
    :decision,
    :system_message,
    :reason,
    :hook_specific_output
  ]

  defmodule Async do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:timeout]

    def to_wire(%__MODULE__{} = o) do
      Output.maybe_put(%{"async" => true}, "asyncTimeout", o.timeout)
    end
  end

  defmodule PermissionDecision do
    @moduledoc false

    defmodule Allow do
      @moduledoc false
      @type t :: %__MODULE__{}
      defstruct [:updated_input, :updated_permissions]

      def to_wire(%__MODULE__{} = o) do
        %{"behavior" => "allow"}
        |> Output.maybe_put("updatedInput", o.updated_input)
        |> Output.maybe_put("updatedPermissions", o.updated_permissions)
      end
    end

    defmodule Deny do
      @moduledoc false
      @type t :: %__MODULE__{}
      defstruct [:message, :interrupt]

      def to_wire(%__MODULE__{} = o) do
        %{"behavior" => "deny"}
        |> Output.maybe_put("message", o.message)
        |> Output.maybe_put("interrupt", o.interrupt)
      end
    end
  end

  defmodule PreToolUse do
    @moduledoc false
    @type t :: %__MODULE__{}

    defstruct [
      :permission_decision,
      :permission_decision_reason,
      :updated_input,
      :additional_context
    ]

    def to_wire(%__MODULE__{} = o) do
      %{"hookEventName" => "PreToolUse"}
      |> Output.maybe_put("permissionDecision", o.permission_decision)
      |> Output.maybe_put("permissionDecisionReason", o.permission_decision_reason)
      |> Output.maybe_put("updatedInput", o.updated_input)
      |> Output.maybe_put("additionalContext", o.additional_context)
    end
  end

  defmodule PostToolUse do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:additional_context, :updated_mcp_tool_output]

    def to_wire(%__MODULE__{} = o) do
      %{"hookEventName" => "PostToolUse"}
      |> Output.maybe_put("additionalContext", o.additional_context)
      |> Output.maybe_put("updatedMCPToolOutput", o.updated_mcp_tool_output)
    end
  end

  defmodule PostToolUseFailure do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:additional_context]

    def to_wire(%__MODULE__{} = o) do
      Output.maybe_put(%{"hookEventName" => "PostToolUseFailure"}, "additionalContext", o.additional_context)
    end
  end

  defmodule UserPromptSubmit do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:additional_context]

    def to_wire(%__MODULE__{} = o) do
      Output.maybe_put(%{"hookEventName" => "UserPromptSubmit"}, "additionalContext", o.additional_context)
    end
  end

  defmodule SessionStart do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:additional_context]

    def to_wire(%__MODULE__{} = o) do
      Output.maybe_put(%{"hookEventName" => "SessionStart"}, "additionalContext", o.additional_context)
    end
  end

  defmodule Notification do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:additional_context]

    def to_wire(%__MODULE__{} = o) do
      Output.maybe_put(%{"hookEventName" => "Notification"}, "additionalContext", o.additional_context)
    end
  end

  defmodule SubagentStart do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:additional_context]

    def to_wire(%__MODULE__{} = o) do
      Output.maybe_put(%{"hookEventName" => "SubagentStart"}, "additionalContext", o.additional_context)
    end
  end

  defmodule PreCompact do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:custom_instructions]

    def to_wire(%__MODULE__{} = o) do
      Output.maybe_put(%{"hookEventName" => "PreCompact"}, "customInstructions", o.custom_instructions)
    end
  end

  defmodule PermissionRequest do
    @moduledoc false
    @type t :: %__MODULE__{}
    defstruct [:decision]

    def to_wire(%__MODULE__{decision: decision}) do
      %{
        "hookEventName" => "PermissionRequest",
        "decision" => decision.__struct__.to_wire(decision)
      }
    end
  end

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

  # Tier 1: bare :ok
  def coerce(:ok, _event), do: %__MODULE__{}

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
  def coerce({:ok, opts}, "PostToolUse"), do: wrap(struct(PostToolUse, opts))
  def coerce({:ok, opts}, "PostToolUseFailure"), do: wrap(struct(PostToolUseFailure, opts))
  def coerce({:ok, opts}, "UserPromptSubmit"), do: wrap(struct(UserPromptSubmit, opts))
  def coerce({:ok, opts}, "SessionStart"), do: wrap(struct(SessionStart, opts))
  def coerce({:ok, opts}, "Notification"), do: wrap(struct(Notification, opts))
  def coerce({:ok, opts}, "SubagentStart"), do: wrap(struct(SubagentStart, opts))
  def coerce({:ok, opts}, "PreCompact"), do: wrap(struct(PreCompact, opts))
  def coerce({:ok, _opts}, _event), do: %__MODULE__{}

  defp wrap(inner), do: %__MODULE__{hook_specific_output: inner}
end
