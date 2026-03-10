defmodule ClaudeCode.Content.MCPToolResultBlock do
  @moduledoc """
  Represents an MCP tool result content block within a Claude message.

  MCP tool result blocks contain the output from an MCP server tool execution.
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.CLI.Parser

  @enforce_keys [:type, :tool_use_id, :content, :is_error]
  defstruct [:type, :tool_use_id, :content, :is_error]

  @type t :: %__MODULE__{
          type: :mcp_tool_result,
          tool_use_id: String.t(),
          content: String.t() | [ClaudeCode.Content.TextBlock.t()],
          is_error: boolean()
        }

  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "mcp_tool_result"} = data) do
    required = ["tool_use_id", "content", "is_error"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      case parse_content(data["content"]) do
        {:ok, parsed_content} ->
          {:ok,
           %__MODULE__{
             type: :mcp_tool_result,
             tool_use_id: data["tool_use_id"],
             content: parsed_content,
             is_error: data["is_error"]
           }}

        {:error, _} = error ->
          error
      end
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}
  defp parse_content(content) when is_binary(content), do: {:ok, content}

  defp parse_content(content) when is_list(content) do
    Parser.parse_contents(content)
  end

  defp parse_content(_), do: {:error, :invalid_content}
end

defimpl String.Chars, for: ClaudeCode.Content.MCPToolResultBlock do
  def to_string(%{content: content}) when is_binary(content), do: content
  def to_string(%{content: blocks}) when is_list(blocks), do: Enum.map_join(blocks, &Kernel.to_string/1)
end
