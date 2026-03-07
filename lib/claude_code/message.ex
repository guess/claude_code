defmodule ClaudeCode.Message do
  @moduledoc """
  Utilities for working with messages from the Claude CLI.

  Messages can be system initialization, assistant responses, user tool results,
  result messages, stream events, conversation compaction boundaries, or
  informational messages (rate limits, tool progress, auth status, etc.).
  This module provides functions to parse and work with any message type.
  """

  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.AuthStatusMessage
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.ElicitationCompleteMessage
  alias ClaudeCode.Message.FilesPersistedEvent
  alias ClaudeCode.Message.HookProgressMessage
  alias ClaudeCode.Message.HookResponseMessage
  alias ClaudeCode.Message.HookStartedMessage
  alias ClaudeCode.Message.LocalCommandOutputMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.StatusMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.TaskNotificationMessage
  alias ClaudeCode.Message.TaskProgressMessage
  alias ClaudeCode.Message.TaskStartedMessage
  alias ClaudeCode.Message.ToolProgressMessage
  alias ClaudeCode.Message.ToolUseSummaryMessage
  alias ClaudeCode.Message.UserMessage

  @type t ::
          SystemMessage.t()
          | CompactBoundaryMessage.t()
          | AssistantMessage.t()
          | UserMessage.t()
          | ResultMessage.t()
          | PartialAssistantMessage.t()
          | RateLimitEvent.t()
          | ToolProgressMessage.t()
          | ToolUseSummaryMessage.t()
          | AuthStatusMessage.t()
          | PromptSuggestionMessage.t()
          | HookStartedMessage.t()
          | HookProgressMessage.t()
          | HookResponseMessage.t()
          | StatusMessage.t()
          | LocalCommandOutputMessage.t()
          | FilesPersistedEvent.t()
          | ElicitationCompleteMessage.t()
          | TaskStartedMessage.t()
          | TaskProgressMessage.t()
          | TaskNotificationMessage.t()

  @doc """
  Checks if a value is any type of message.
  """
  @spec message?(any()) :: boolean()
  def message?(%SystemMessage{}), do: true
  def message?(%CompactBoundaryMessage{}), do: true
  def message?(%AssistantMessage{}), do: true
  def message?(%UserMessage{}), do: true
  def message?(%ResultMessage{}), do: true
  def message?(%PartialAssistantMessage{}), do: true
  def message?(%RateLimitEvent{}), do: true
  def message?(%ToolProgressMessage{}), do: true
  def message?(%ToolUseSummaryMessage{}), do: true
  def message?(%AuthStatusMessage{}), do: true
  def message?(%PromptSuggestionMessage{}), do: true
  def message?(%HookStartedMessage{}), do: true
  def message?(%HookProgressMessage{}), do: true
  def message?(%HookResponseMessage{}), do: true
  def message?(%StatusMessage{}), do: true
  def message?(%LocalCommandOutputMessage{}), do: true
  def message?(%FilesPersistedEvent{}), do: true
  def message?(%ElicitationCompleteMessage{}), do: true
  def message?(%TaskStartedMessage{}), do: true
  def message?(%TaskProgressMessage{}), do: true
  def message?(%TaskNotificationMessage{}), do: true
  def message?(_), do: false

  @doc """
  Returns the type of a message.
  """
  @spec message_type(t()) ::
          :system
          | :assistant
          | :user
          | :result
          | :stream_event
          | :rate_limit_event
          | :tool_progress
          | :tool_use_summary
          | :auth_status
          | :prompt_suggestion
  def message_type(%SystemMessage{type: type}), do: type
  def message_type(%CompactBoundaryMessage{type: type}), do: type
  def message_type(%AssistantMessage{type: type}), do: type
  def message_type(%UserMessage{type: type}), do: type
  def message_type(%ResultMessage{type: type}), do: type
  def message_type(%PartialAssistantMessage{type: type}), do: type
  def message_type(%RateLimitEvent{type: type}), do: type
  def message_type(%ToolProgressMessage{type: type}), do: type
  def message_type(%ToolUseSummaryMessage{type: type}), do: type
  def message_type(%AuthStatusMessage{type: type}), do: type
  def message_type(%PromptSuggestionMessage{type: type}), do: type
  def message_type(%HookStartedMessage{type: type}), do: type
  def message_type(%HookProgressMessage{type: type}), do: type
  def message_type(%HookResponseMessage{type: type}), do: type
  def message_type(%StatusMessage{type: type}), do: type
  def message_type(%LocalCommandOutputMessage{type: type}), do: type
  def message_type(%FilesPersistedEvent{type: type}), do: type
  def message_type(%ElicitationCompleteMessage{type: type}), do: type
  def message_type(%TaskStartedMessage{type: type}), do: type
  def message_type(%TaskProgressMessage{type: type}), do: type
  def message_type(%TaskNotificationMessage{type: type}), do: type

  @doc """
  Parses a camelCase permission mode string into an atom.

  Returns `fallback` (default `nil`) for unrecognized values.
  """
  @spec parse_permission_mode(String.t() | nil, atom()) :: atom()
  def parse_permission_mode(value, fallback \\ nil)
  def parse_permission_mode("default", _fallback), do: :default
  def parse_permission_mode("acceptEdits", _fallback), do: :accept_edits
  def parse_permission_mode("bypassPermissions", _fallback), do: :bypass_permissions
  def parse_permission_mode("delegate", _fallback), do: :delegate
  def parse_permission_mode("dontAsk", _fallback), do: :dont_ask
  def parse_permission_mode("plan", _fallback), do: :plan
  def parse_permission_mode(_, fallback), do: fallback
end
