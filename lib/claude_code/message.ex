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
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
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
end
