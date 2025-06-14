defmodule ClaudeCode.Content.ToolResult do
  @moduledoc """
  Represents a tool result content block within a Claude message.
  
  Tool result blocks contain the output from a tool execution, which can be
  either successful results or error messages.
  """
  
  @enforce_keys [:type, :tool_use_id, :content, :is_error]
  defstruct [:type, :tool_use_id, :content, :is_error]
  
  @type t :: %__MODULE__{
    type: :tool_result,
    tool_use_id: String.t(),
    content: String.t(),
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
      result = %__MODULE__{
        type: :tool_result,
        tool_use_id: data["tool_use_id"],
        content: data["content"],
        is_error: Map.get(data, "is_error", false)
      }
      
      {:ok, result}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end
  
  def new(_), do: {:error, :invalid_content_type}
  
  @doc """
  Type guard to check if a value is a ToolResult content block.
  """
  @spec is_tool_result_content?(any()) :: boolean()
  def is_tool_result_content?(%__MODULE__{type: :tool_result}), do: true
  def is_tool_result_content?(_), do: false
end