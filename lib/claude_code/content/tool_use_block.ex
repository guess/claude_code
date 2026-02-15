defmodule ClaudeCode.Content.ToolUseBlock do
  @moduledoc """
  Represents a tool use content block within a Claude message.

  Tool use blocks indicate that Claude wants to invoke a specific tool
  with the given parameters.
  """

  @enforce_keys [:type, :id, :name, :input]
  defstruct [:type, :id, :name, :input, :caller]

  @type t :: %__MODULE__{
          type: :tool_use,
          id: String.t(),
          name: String.t(),
          input: map(),
          caller: map() | nil
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
        input: data["input"],
        caller: data["caller"]
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
  @spec tool_use_content?(any()) :: boolean()
  def tool_use_content?(%__MODULE__{type: :tool_use}), do: true
  def tool_use_content?(_), do: false
end

defimpl Jason.Encoder, for: ClaudeCode.Content.ToolUseBlock do
  def encode(block, opts) do
    block
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> Jason.Encoder.Map.encode(opts)
  end
end

defimpl JSON.Encoder, for: ClaudeCode.Content.ToolUseBlock do
  def encode(block, encoder) do
    block
    |> ClaudeCode.JSONEncoder.to_encodable()
    |> JSON.Encoder.Map.encode(encoder)
  end
end
