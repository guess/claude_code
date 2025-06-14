defmodule ClaudeCode.Message do
  @moduledoc """
  Defines message structures for Claude Code communication.

  This module provides structs and functions for handling the various
  message types that flow between the SDK and the Claude CLI.
  """

  @doc """
  Represents a message from Claude (assistant).

  For Phase 1, we store the entire content as a string.
  In Phase 2, this will be enhanced to handle content blocks.
  """
  defstruct [:type, :content, :metadata]

  @type t :: %__MODULE__{
          type: atom(),
          content: String.t(),
          metadata: map()
        }

  @doc """
  Creates a new message struct from parsed JSON data.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"type" => "assistant", "message" => message} = json) do
    # Extract text content from the assistant message structure
    content =
      case message do
        %{"content" => [%{"text" => text} | _]} -> text
        _ -> ""
      end

    %__MODULE__{
      type: :assistant,
      content: content,
      metadata: Map.drop(json, ["type", "message"])
    }
  end

  def from_json(%{"type" => "error", "message" => message} = json) do
    %__MODULE__{
      type: :error,
      content: message,
      metadata: Map.drop(json, ["type", "message"])
    }
  end

  def from_json(%{"type" => type} = json) do
    # Generic handler for other message types
    %__MODULE__{
      type: String.to_atom(type),
      content: Map.get(json, "content", ""),
      metadata: Map.drop(json, ["type", "content"])
    }
  end

  @doc """
  Checks if a message is an error message.
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{type: :error}), do: true
  def error?(_), do: false

  @doc """
  Checks if a message is from the assistant.
  """
  @spec assistant?(t()) :: boolean()
  def assistant?(%__MODULE__{type: :assistant}), do: true
  def assistant?(_), do: false
end
