defmodule ClaudeCode.Content do
  @moduledoc """
  Utilities for working with content blocks in Claude messages.
  
  Content blocks can be text, tool use requests, or tool results.
  This module provides functions to parse and work with any content type.
  """
  
  alias ClaudeCode.Content.{Text, ToolUse, ToolResult}
  
  @type t :: Text.t() | ToolUse.t() | ToolResult.t()
  
  @doc """
  Parses a content block from JSON data based on its type.
  
  ## Examples
  
      iex> Content.parse(%{"type" => "text", "text" => "Hello"})
      {:ok, %Text{type: :text, text: "Hello"}}
      
      iex> Content.parse(%{"type" => "unknown"})
      {:error, {:unknown_content_type, "unknown"}}
  """
  @spec parse(map()) :: {:ok, t()} | {:error, term()}
  def parse(%{"type" => type} = data) do
    case type do
      "text" -> Text.new(data)
      "tool_use" -> ToolUse.new(data)
      "tool_result" -> ToolResult.new(data)
      other -> {:error, {:unknown_content_type, other}}
    end
  end
  
  def parse(_), do: {:error, :missing_type}
  
  @doc """
  Parses a list of content blocks.
  
  Returns {:ok, contents} if all blocks parse successfully,
  or {:error, {:parse_error, index, error}} for the first failure.
  """
  @spec parse_all(list(map())) :: {:ok, [t()]} | {:error, term()}
  def parse_all(blocks) when is_list(blocks) do
    blocks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {block, index}, {:ok, acc} ->
      case parse(block) do
        {:ok, content} -> {:cont, {:ok, [content | acc]}}
        {:error, error} -> {:halt, {:error, {:parse_error, index, error}}}
      end
    end)
    |> case do
      {:ok, contents} -> {:ok, Enum.reverse(contents)}
      error -> error
    end
  end
  
  @doc """
  Checks if a value is any type of content block.
  """
  @spec is_content?(any()) :: boolean()
  def is_content?(%Text{}), do: true
  def is_content?(%ToolUse{}), do: true
  def is_content?(%ToolResult{}), do: true
  def is_content?(_), do: false
  
  @doc """
  Returns the type of a content block.
  """
  @spec content_type(t()) :: :text | :tool_use | :tool_result
  def content_type(%Text{type: type}), do: type
  def content_type(%ToolUse{type: type}), do: type
  def content_type(%ToolResult{type: type}), do: type
end