defmodule ClaudeCode.Content do
  @moduledoc """
  Utilities for working with content blocks in Claude messages.

  Content blocks can be text, thinking, tool use requests, tool results,
  server tool invocations, MCP tool interactions, or compaction summaries.
  This module provides functions to parse and work with any content type.
  """

  alias ClaudeCode.Content.CompactionBlock
  alias ClaudeCode.Content.ContainerUploadBlock
  alias ClaudeCode.Content.DocumentBlock
  alias ClaudeCode.Content.ImageBlock
  alias ClaudeCode.Content.MCPToolResultBlock
  alias ClaudeCode.Content.MCPToolUseBlock
  alias ClaudeCode.Content.RedactedThinkingBlock
  alias ClaudeCode.Content.ServerToolResultBlock
  alias ClaudeCode.Content.ServerToolUseBlock
  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock

  @type t ::
          TextBlock.t()
          | ThinkingBlock.t()
          | RedactedThinkingBlock.t()
          | ToolUseBlock.t()
          | ToolResultBlock.t()
          | ServerToolUseBlock.t()
          | ServerToolResultBlock.t()
          | MCPToolUseBlock.t()
          | MCPToolResultBlock.t()
          | ImageBlock.t()
          | DocumentBlock.t()
          | ContainerUploadBlock.t()
          | CompactionBlock.t()

  @doc """
  Checks if a value is any type of content block.
  """
  @spec content?(any()) :: boolean()
  def content?(%TextBlock{}), do: true
  def content?(%ThinkingBlock{}), do: true
  def content?(%RedactedThinkingBlock{}), do: true
  def content?(%ToolUseBlock{}), do: true
  def content?(%ToolResultBlock{}), do: true
  def content?(%ServerToolUseBlock{}), do: true
  def content?(%ServerToolResultBlock{}), do: true
  def content?(%MCPToolUseBlock{}), do: true
  def content?(%MCPToolResultBlock{}), do: true
  def content?(%ImageBlock{}), do: true
  def content?(%DocumentBlock{}), do: true
  def content?(%ContainerUploadBlock{}), do: true
  def content?(%CompactionBlock{}), do: true
  def content?(_), do: false

  @type delta ::
          %{type: :text_delta, text: String.t()}
          | %{type: :input_json_delta, partial_json: String.t()}
          | %{type: :thinking_delta, thinking: String.t()}
          | %{type: :signature_delta, signature: String.t()}
          | %{type: :citations_delta, citation: map()}
          | %{type: :compaction_delta, content: String.t() | nil}

  @doc """
  Parses a content block delta from a stream event into a typed map.

  ## Examples

      iex> ClaudeCode.Content.parse_delta(%{"type" => "text_delta", "text" => "Hi"})
      {:ok, %{type: :text_delta, text: "Hi"}}

      iex> ClaudeCode.Content.parse_delta(%{"type" => "future_delta"})
      {:error, {:unknown_delta_type, "future_delta"}}

  """
  @spec parse_delta(map()) :: {:ok, delta()} | {:error, term()}
  def parse_delta(%{"type" => "text_delta", "text" => text}), do: {:ok, %{type: :text_delta, text: text}}

  def parse_delta(%{"type" => "input_json_delta", "partial_json" => json}),
    do: {:ok, %{type: :input_json_delta, partial_json: json}}

  def parse_delta(%{"type" => "thinking_delta", "thinking" => thinking}),
    do: {:ok, %{type: :thinking_delta, thinking: thinking}}

  def parse_delta(%{"type" => "signature_delta", "signature" => signature}),
    do: {:ok, %{type: :signature_delta, signature: signature}}

  def parse_delta(%{"type" => "citations_delta", "citation" => citation}),
    do: {:ok, %{type: :citations_delta, citation: citation}}

  def parse_delta(%{"type" => "compaction_delta", "content" => content}),
    do: {:ok, %{type: :compaction_delta, content: content}}

  def parse_delta(%{"type" => type}), do: {:error, {:unknown_delta_type, type}}

  def parse_delta(_), do: {:error, :missing_type}

  @doc """
  Returns the type of a content block.
  """
  @spec content_type(t()) ::
          :text
          | :thinking
          | :redacted_thinking
          | :tool_use
          | :tool_result
          | :server_tool_use
          | ServerToolResultBlock.server_tool_result_type()
          | :mcp_tool_use
          | :mcp_tool_result
          | :image
          | :document
          | :container_upload
          | :compaction
  def content_type(%TextBlock{type: type}), do: type
  def content_type(%ThinkingBlock{type: type}), do: type
  def content_type(%RedactedThinkingBlock{type: type}), do: type
  def content_type(%ToolUseBlock{type: type}), do: type
  def content_type(%ToolResultBlock{type: type}), do: type
  def content_type(%ServerToolUseBlock{type: type}), do: type
  def content_type(%ServerToolResultBlock{type: type}), do: type
  def content_type(%MCPToolUseBlock{type: type}), do: type
  def content_type(%MCPToolResultBlock{type: type}), do: type
  def content_type(%ImageBlock{type: type}), do: type
  def content_type(%DocumentBlock{type: type}), do: type
  def content_type(%ContainerUploadBlock{type: type}), do: type
  def content_type(%CompactionBlock{type: type}), do: type
end
