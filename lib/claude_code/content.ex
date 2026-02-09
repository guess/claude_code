defmodule ClaudeCode.Content do
  @moduledoc """
  Utilities for working with content blocks in Claude messages.

  Content blocks can be text, thinking, tool use requests, or tool results.
  This module provides functions to parse and work with any content type.
  """

  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock

  @type t :: TextBlock.t() | ThinkingBlock.t() | ToolUseBlock.t() | ToolResultBlock.t()

  @doc """
  Checks if a value is any type of content block.
  """
  @spec content?(any()) :: boolean()
  def content?(%TextBlock{}), do: true
  def content?(%ThinkingBlock{}), do: true
  def content?(%ToolUseBlock{}), do: true
  def content?(%ToolResultBlock{}), do: true
  def content?(_), do: false

  @doc """
  Returns the type of a content block.
  """
  @spec content_type(t()) :: :text | :thinking | :tool_use | :tool_result
  def content_type(%TextBlock{type: type}), do: type
  def content_type(%ThinkingBlock{type: type}), do: type
  def content_type(%ToolUseBlock{type: type}), do: type
  def content_type(%ToolResultBlock{type: type}), do: type
end
