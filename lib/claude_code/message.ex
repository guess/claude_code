defmodule ClaudeCode.Message do
  @moduledoc """
  Utilities for working with messages from the Claude CLI.

  Messages can be system initialization, assistant responses, user tool results,
  result messages, stream events, or conversation compaction boundaries.
  This module provides functions to parse and work with any message type.
  """

  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.UserMessage

  @type t ::
          SystemMessage.t()
          | CompactBoundaryMessage.t()
          | AssistantMessage.t()
          | UserMessage.t()
          | ResultMessage.t()
          | PartialAssistantMessage.t()

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
  def message?(_), do: false

  @doc """
  Returns the type of a message.
  """
  @spec message_type(t()) :: :system | :assistant | :user | :result | :stream_event
  def message_type(%SystemMessage{type: type}), do: type
  def message_type(%CompactBoundaryMessage{type: type}), do: type
  def message_type(%AssistantMessage{type: type}), do: type
  def message_type(%UserMessage{type: type}), do: type
  def message_type(%ResultMessage{type: type}), do: type
  def message_type(%PartialAssistantMessage{type: type}), do: type
end
