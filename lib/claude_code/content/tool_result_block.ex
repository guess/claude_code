defmodule ClaudeCode.Content.ToolResultBlock do
  @moduledoc """
  Represents a tool result content block within a Claude message.

  Tool result blocks contain the output from a tool execution, which can be
  either successful results or error messages.
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.CLI.Parser

  @enforce_keys [:type, :tool_use_id, :content, :is_error]
  defstruct [:type, :tool_use_id, :content, :is_error]

  @type t :: %__MODULE__{
          type: :tool_result,
          tool_use_id: String.t(),
          content: [ClaudeCode.Content.TextBlock.t()],
          is_error: boolean()
        }

  @doc """
  Creates a new ToolResult content block from JSON data.

  ## Examples

      iex> ToolResult.new(%{"type" => "tool_result", "tool_use_id" => "123", "content" => "OK"})
      {:ok, %ToolResult{type: :tool_result, tool_use_id: "123", content: "OK", is_error: false}}

      iex> ToolResult.new(%{"type" => "text"})
      {:error, :invalid_content_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "tool_result"} = data) do
    required = ["tool_use_id", "content"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      case parse_content(data["content"]) do
        {:ok, parsed_content} ->
          result = %__MODULE__{
            type: :tool_result,
            tool_use_id: data["tool_use_id"],
            content: parsed_content,
            is_error: Map.get(data, "is_error", false)
          }

          {:ok, result}

        {:error, _} = error ->
          error
      end
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}
  # Private helpers

  defp parse_content(content) when is_binary(content), do: {:ok, content}
  defp parse_content(content) when is_list(content), do: Parser.parse_contents(content)
  defp parse_content(_), do: {:error, :invalid_content}
end
