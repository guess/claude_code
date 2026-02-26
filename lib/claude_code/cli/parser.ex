defmodule ClaudeCode.CLI.Parser do
  @moduledoc """
  Parses CLI JSON output into message and content structs.

  This module is the CLI protocol layer responsible for converting
  newline-delimited JSON from `--output-format stream-json` into
  the adapter-agnostic struct types defined in `ClaudeCode.Message.*`
  and `ClaudeCode.Content.*`.

  A future native API adapter would produce the same structs but from
  a different wire format. The struct definitions and type-checking
  functions remain in `ClaudeCode.Message` and `ClaudeCode.Content`.
  """

  alias ClaudeCode.Content.TextBlock
  alias ClaudeCode.Content.ThinkingBlock
  alias ClaudeCode.Content.ToolResultBlock
  alias ClaudeCode.Content.ToolUseBlock
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.AuthStatusMessage
  alias ClaudeCode.Message.CompactBoundaryMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.ToolProgressMessage
  alias ClaudeCode.Message.ToolUseSummaryMessage
  alias ClaudeCode.Message.UserMessage

  # -- Message parsing --------------------------------------------------------

  # Maps wire type strings to their parser module's new/1 function.
  # "system" is handled separately via parse_system/1 (dispatches on subtype).
  @message_parsers %{
    "assistant" => &AssistantMessage.new/1,
    "user" => &UserMessage.new/1,
    "result" => &ResultMessage.new/1,
    "stream_event" => &PartialAssistantMessage.new/1,
    "rate_limit_event" => &RateLimitEvent.new/1,
    "tool_progress" => &ToolProgressMessage.new/1,
    "tool_use_summary" => &ToolUseSummaryMessage.new/1,
    "auth_status" => &AuthStatusMessage.new/1,
    "prompt_suggestion" => &PromptSuggestionMessage.new/1
  }

  @doc """
  Parses a decoded JSON map into a message struct.

  Dispatches on `"type"` to the appropriate message module's `new/1`
  constructor.

  ## Examples

      iex> ClaudeCode.CLI.Parser.parse_message(%{"type" => "system", "subtype" => "init", ...})
      {:ok, %ClaudeCode.Message.SystemMessage{...}}

      iex> ClaudeCode.CLI.Parser.parse_message(%{"type" => "unknown"})
      {:error, {:unknown_message_type, "unknown"}}
  """
  @spec parse_message(map()) :: {:ok, ClaudeCode.Message.t()} | {:error, term()}
  def parse_message(%{"type" => "system"} = data), do: parse_system(data)

  def parse_message(%{"type" => type} = data) do
    case Map.fetch(@message_parsers, type) do
      {:ok, parser} -> parser.(data)
      :error -> {:error, {:unknown_message_type, type}}
    end
  end

  def parse_message(_), do: {:error, :missing_type}

  @doc """
  Parses a list of decoded JSON maps into message structs.

  Returns `{:ok, messages}` if all messages parse successfully,
  or `{:error, {:parse_error, index, error}}` for the first failure.
  """
  @spec parse_all_messages(list(map())) :: {:ok, [ClaudeCode.Message.t()]} | {:error, term()}
  def parse_all_messages(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {message, index}, {:ok, acc} ->
      case parse_message(message) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, error} -> {:halt, {:error, {:parse_error, index, error}}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  @doc """
  Parses a newline-delimited JSON stream from the CLI.

  This is the format output by the CLI with `--output-format stream-json`.
  Each line is a complete JSON object representing a single message.
  """
  @spec parse_stream(String.t()) :: {:ok, [ClaudeCode.Message.t()]} | {:error, term()}
  def parse_stream(stream) when is_binary(stream) do
    stream
    |> String.split("\n", trim: true)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {line, index}, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, json} ->
          case parse_message(json) do
            {:ok, message} -> {:cont, {:ok, [message | acc]}}
            {:error, error} -> {:halt, {:error, {:parse_error, index, error}}}
          end

        {:error, error} ->
          {:halt, {:error, {:json_decode_error, index, error}}}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  # -- Content parsing --------------------------------------------------------

  @doc """
  Parses a decoded JSON map into a content block struct.

  Dispatches on `"type"` to the appropriate content module's `new/1`
  constructor.

  ## Examples

      iex> ClaudeCode.CLI.Parser.parse_content(%{"type" => "text", "text" => "Hello"})
      {:ok, %ClaudeCode.Content.TextBlock{type: :text, text: "Hello"}}

      iex> ClaudeCode.CLI.Parser.parse_content(%{"type" => "unknown"})
      {:error, {:unknown_content_type, "unknown"}}
  """
  @spec parse_content(map()) :: {:ok, ClaudeCode.Content.t()} | {:error, term()}
  def parse_content(%{"type" => type} = data) do
    case type do
      "text" -> TextBlock.new(data)
      "thinking" -> ThinkingBlock.new(data)
      "tool_use" -> ToolUseBlock.new(data)
      "tool_result" -> ToolResultBlock.new(data)
      other -> {:error, {:unknown_content_type, other}}
    end
  end

  def parse_content(_), do: {:error, :missing_type}

  @doc """
  Parses a list of decoded JSON maps into content block structs.

  Returns `{:ok, contents}` if all blocks parse successfully,
  or `{:error, {:parse_error, index, error}}` for the first failure.
  """
  @spec parse_all_contents(list(map())) :: {:ok, [ClaudeCode.Content.t()]} | {:error, term()}
  def parse_all_contents(blocks) when is_list(blocks) do
    blocks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {block, index}, {:ok, acc} ->
      case parse_content(block) do
        {:ok, content} -> {:cont, {:ok, [content | acc]}}
        {:error, error} -> {:halt, {:error, {:parse_error, index, error}}}
      end
    end)
    |> case do
      {:ok, contents} -> {:ok, Enum.reverse(contents)}
      error -> error
    end
  end

  # -- Private: system message dispatch ---------------------------------------

  defp parse_system(%{"subtype" => "compact_boundary"} = data) do
    CompactBoundaryMessage.new(data)
  end

  defp parse_system(%{"subtype" => _} = data) do
    SystemMessage.new(data)
  end

  defp parse_system(_), do: {:error, :invalid_system_subtype}
end
