defmodule ClaudeCode.Content.ToolUse do
  @moduledoc """
  Represents a tool use content block within a Claude message.

  Tool use blocks indicate that Claude wants to invoke a specific tool
  with the given parameters.
  """

  @enforce_keys [:type, :id, :name, :input]
  defstruct [:type, :id, :name, :input]

  @type t :: %__MODULE__{
          type: :tool_use,
          id: String.t(),
          name: String.t(),
          input: map()
        }

  @doc """
  Creates a new ToolUse content block from JSON data.

  ## Examples

      iex> ToolUse.new(%{"type" => "tool_use", "id" => "123", "name" => "Read", "input" => %{}})
      {:ok, %ToolUse{type: :tool_use, id: "123", name: "Read", input: %{}}}
      
      iex> ToolUse.new(%{"type" => "text"})
      {:error, :invalid_content_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "tool_use"} = data) do
    required = ["id", "name", "input"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      content = %__MODULE__{
        type: :tool_use,
        id: data["id"],
        name: data["name"],
        input: data["input"]
      }

      {:ok, content}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}

  @doc """
  Type guard to check if a value is a ToolUse content block.
  """
  @spec is_tool_use_content?(any()) :: boolean()
  def is_tool_use_content?(%__MODULE__{type: :tool_use}), do: true
  def is_tool_use_content?(_), do: false
end
