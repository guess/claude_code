defmodule ClaudeCode.Content do
  @moduledoc """
  Utilities for working with content blocks in Claude messages.

  Content blocks can be text, thinking, tool use requests, or tool results.
  This module provides functions to parse and work with any content type.
  """

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock

  @type t :: TextBlock.t() | ThinkingBlock.t() | ToolUseBlock.t() | ToolResultBlock.t()

  @doc """
  Parses a content block from JSON data based on its type.

  Delegates to `ClaudeCode.CLI.Parser.parse_content/1`.

  ## Examples

      iex> Content.parse(%{"type" => "text", "text" => "Hello"})
      {:ok, %TextBlock{type: :text, text: "Hello"}}

      iex> Content.parse(%{"type" => "unknown"})
      {:error, {:unknown_content_type, "unknown"}}
  """
  defdelegate parse(data), to: Parser, as: :parse_content

  @doc """
  Parses a list of content blocks.

  Delegates to `ClaudeCode.CLI.Parser.parse_all_contents/1`.

  Returns {:ok, contents} if all blocks parse successfully,
  or {:error, {:parse_error, index, error}} for the first failure.
  """
  defdelegate parse_all(blocks), to: Parser, as: :parse_all_contents

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
