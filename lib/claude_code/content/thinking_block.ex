defmodule ClaudeCode.Content.ThinkingBlock do
  @moduledoc """
  Represents a thinking content block within a Claude message.

  Thinking blocks contain Claude's extended reasoning, visible when
  extended thinking is enabled on supported models.
  """

  @enforce_keys [:type, :thinking, :signature]
  defstruct [:type, :thinking, :signature]

  @type t :: %__MODULE__{
          type: :thinking,
          thinking: String.t(),
          signature: String.t()
        }

  @doc """
  Creates a new Thinking content block from JSON data.

  ## Examples

      iex> Thinking.new(%{"type" => "thinking", "thinking" => "Let me reason...", "signature" => "sig_123"})
      {:ok, %Thinking{type: :thinking, thinking: "Let me reason...", signature: "sig_123"}}

      iex> Thinking.new(%{"type" => "text"})
      {:error, :invalid_content_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "thinking"} = data) do
    required = ["thinking", "signature"]
    missing = Enum.filter(required, &(not Map.has_key?(data, &1)))

    if Enum.empty?(missing) do
      content = %__MODULE__{
        type: :thinking,
        thinking: data["thinking"],
        signature: data["signature"]
      }

      {:ok, content}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_content_type}

  @doc """
  Type guard to check if a value is a Thinking content block.
  """
  @spec thinking_content?(any()) :: boolean()
  def thinking_content?(%__MODULE__{type: :thinking}), do: true
  def thinking_content?(_), do: false
end
