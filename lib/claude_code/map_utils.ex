defmodule ClaudeCode.MapUtils do
  @moduledoc false

  # Explicit string→atom mapping for keys the CLI sends that may not already
  # exist in the atom table. Checked first by safe_atomize_key/1 so we don't
  # rely on atom-table side effects.
  #
  # Sources: BaseHookInput, per-event hook inputs, SubagentContextMixin
  # See: .claude/skills/cli-sync/captured/ts-sdk-types.d.ts (authoritative)
  #      .claude/skills/cli-sync/captured/python-sdk-types.py
  @known_keys %{
    # BaseHookInput
    "session_id" => :session_id,
    "transcript_path" => :transcript_path,
    "cwd" => :cwd,
    "permission_mode" => :permission_mode,
    "hook_event_name" => :hook_event_name,
    "agent_id" => :agent_id,
    "agent_type" => :agent_type,
    # PreToolUse / PostToolUse / PostToolUseFailure
    "tool_name" => :tool_name,
    "tool_input" => :tool_input,
    "tool_use_id" => :tool_use_id,
    "tool_response" => :tool_response,
    "is_interrupt" => :is_interrupt,
    # Stop / SubagentStop
    "stop_hook_active" => :stop_hook_active,
    "agent_transcript_path" => :agent_transcript_path,
    "last_assistant_message" => :last_assistant_message,
    # PreCompact / Setup
    "custom_instructions" => :custom_instructions,
    # Notification
    "notification_type" => :notification_type,
    # PermissionRequest / can_use_tool
    "permission_suggestions" => :permission_suggestions,
    "suggestions" => :suggestions,
    "signal" => :signal,
    "blocked_path" => :blocked_path,
    "input" => :input,
    "decision_reason" => :decision_reason,
    "description" => :description,
    # UserPromptSubmit
    "prompt" => :prompt,
    # SessionStart
    "source" => :source,
    "model" => :model,
    # SessionEnd
    "reason" => :reason,
    # Setup (trigger shared with PreCompact — already :trigger in atom table)
    "trigger" => :trigger,
    # ConfigChange
    "file_path" => :file_path,
    # InstructionsLoaded
    "memory_type" => :memory_type,
    "load_reason" => :load_reason,
    "globs" => :globs,
    "trigger_file_path" => :trigger_file_path,
    "parent_file_path" => :parent_file_path,
    # Notification (message/title are common atoms, but be explicit)
    "message" => :message,
    "title" => :title,
    # Elicitation / ElicitationResult
    "mcp_server_name" => :mcp_server_name,
    "mode" => :mode,
    "url" => :url,
    "elicitation_id" => :elicitation_id,
    "requested_schema" => :requested_schema,
    "action" => :action,
    "content" => :content,
    # TaskCompleted
    "task_id" => :task_id,
    "task_subject" => :task_subject,
    "task_description" => :task_description,
    "teammate_name" => :teammate_name,
    "team_name" => :team_name,
    # WorktreeCreate
    "name" => :name,
    # WorktreeRemove
    "worktree_path" => :worktree_path,
    # PostToolUseFailure
    "error" => :error
  }

  @doc """
  Converts a string key to an existing atom, or returns the string unchanged.

  First checks an explicit mapping of known CLI keys, then falls back to
  `:erlang.binary_to_existing_atom/2`. If the atom does not already exist
  in the atom table and is not in the known keys map, the original string
  is returned.
  """
  @spec safe_atomize_key(atom() | String.t()) :: atom() | String.t()
  def safe_atomize_key(key) when is_atom(key), do: key

  def safe_atomize_key(key) when is_binary(key) do
    Map.get(@known_keys, key, :erlang.binary_to_existing_atom(key, :utf8))
  catch
    :error, :badarg -> key
  end

  @doc """
  Safely atomizes top-level string keys in a map.

  Known keys (from the explicit mapping or the atom table) become atoms;
  unknown keys stay as strings. Values are not modified.
  """
  @spec safe_atomize_keys(map()) :: map()
  def safe_atomize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {safe_atomize_key(key), value} end)
  end

  @doc """
  Recursively atomizes string keys in nested maps and lists.

  Known keys become atoms; unknown keys stay as strings.
  """
  @spec safe_atomize_keys_recursive(term()) :: term()
  def safe_atomize_keys_recursive(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {safe_atomize_key(key), safe_atomize_keys_recursive(value)} end)
  end

  def safe_atomize_keys_recursive(list) when is_list(list) do
    Enum.map(list, &safe_atomize_keys_recursive/1)
  end

  def safe_atomize_keys_recursive(value), do: value
end
