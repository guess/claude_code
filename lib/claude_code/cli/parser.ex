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
  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.AuthStatusMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage.CompactBoundary
  alias ClaudeCode.Message.SystemMessage.ElicitationComplete
  alias ClaudeCode.Message.SystemMessage.FilesPersisted
  alias ClaudeCode.Message.SystemMessage.HookProgress
  alias ClaudeCode.Message.SystemMessage.HookResponse
  alias ClaudeCode.Message.SystemMessage.HookStarted
  alias ClaudeCode.Message.SystemMessage.Init
  alias ClaudeCode.Message.SystemMessage.LocalCommandOutput
  alias ClaudeCode.Message.SystemMessage.Status
  alias ClaudeCode.Message.SystemMessage.TaskNotification
  alias ClaudeCode.Message.SystemMessage.TaskProgress
  alias ClaudeCode.Message.SystemMessage.TaskStarted
  alias ClaudeCode.Message.ToolProgressMessage
  alias ClaudeCode.Message.ToolUseSummaryMessage
  alias ClaudeCode.Message.UserMessage

  @doc """
  Recursively normalizes all string keys in a map using `Macro.underscore/1`.

  This ensures consistent snake_case keys regardless of whether the source
  uses camelCase (history files) or snake_case (live CLI output).
  Already-snake_case keys pass through unchanged.

  ## Examples

      iex> ClaudeCode.CLI.Parser.normalize_keys(%{"sessionId" => "123", "type" => "user"})
      %{"session_id" => "123", "type" => "user"}

      iex> ClaudeCode.CLI.Parser.normalize_keys(%{"nested" => %{"inputTokens" => 5}})
      %{"nested" => %{"input_tokens" => 5}}
  """
  # Tool input maps contain user-defined parameter names that must not be normalized.
  @opaque_keys MapSet.new(["input", "tool_input"])

  @spec normalize_keys(term()) :: term()
  def normalize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      normalized_key = if is_binary(key), do: Macro.underscore(key), else: key

      normalized_value =
        if normalized_key in @opaque_keys, do: value, else: normalize_keys(value)

      {normalized_key, normalized_value}
    end)
  end

  def normalize_keys(list) when is_list(list), do: Enum.map(list, &normalize_keys/1)
  def normalize_keys(value), do: value

  # -- Message parsing --------------------------------------------------------

  @system_parsers Map.merge(
                    %{
                      "init" => &Init.new/1,
                      "compact_boundary" => &CompactBoundary.new/1,
                      "hook_started" => &HookStarted.new/1,
                      "hook_progress" => &HookProgress.new/1,
                      "hook_response" => &HookResponse.new/1,
                      "status" => &Status.new/1,
                      "local_command_output" => &LocalCommandOutput.new/1,
                      "files_persisted" => &FilesPersisted.new/1,
                      "elicitation_complete" => &ElicitationComplete.new/1,
                      "task_started" => &TaskStarted.new/1,
                      "task_progress" => &TaskProgress.new/1,
                      "task_notification" => &TaskNotification.new/1
                    },
                    Application.compile_env(:claude_code, :system_parsers, %{})
                  )

  @message_parsers Map.merge(
                     %{
                       "assistant" => &AssistantMessage.new/1,
                       "user" => &UserMessage.new/1,
                       "result" => &ResultMessage.new/1,
                       "stream_event" => &PartialAssistantMessage.new/1,
                       "rate_limit_event" => &RateLimitEvent.new/1,
                       "tool_progress" => &ToolProgressMessage.new/1,
                       "tool_use_summary" => &ToolUseSummaryMessage.new/1,
                       "auth_status" => &AuthStatusMessage.new/1,
                       "prompt_suggestion" => &PromptSuggestionMessage.new/1
                     },
                     Application.compile_env(:claude_code, :message_parsers, %{})
                   )

  @doc """
  Parses a decoded JSON map into a message struct.

  Normalizes keys and dispatches on `"type"` to the appropriate message
  module's `new/1` constructor.

  ## Examples

      iex> ClaudeCode.CLI.Parser.parse_message(%{"type" => "system", "subtype" => "init", ...})
      {:ok, %ClaudeCode.Message.SystemMessage.Init{...}}

      iex> ClaudeCode.CLI.Parser.parse_message(%{"type" => "unknown"})
      {:error, {:unknown_message_type, "unknown"}}
  """
  @spec parse_message(map()) :: {:ok, ClaudeCode.Message.t() | struct()} | {:error, term()}
  def parse_message(data) when is_map(data) do
    data = normalize_keys(data)

    case data do
      %{"type" => "system", "subtype" => subtype} when is_binary(subtype) ->
        case Map.fetch(@system_parsers, subtype) do
          {:ok, parser} -> parser.(data)
          :error -> {:error, {:unknown_system_subtype, subtype}}
        end

      %{"type" => "system"} ->
        {:error, :invalid_system_subtype}

      %{"type" => type} ->
        case Map.fetch(@message_parsers, type) do
          {:ok, parser} -> parser.(data)
          :error -> {:error, {:unknown_message_type, type}}
        end

      _ ->
        {:error, :missing_type}
    end
  end

  def parse_message(_), do: {:error, :missing_type}

  @doc """
  Parses a list of decoded JSON maps into message structs.

  Unknown message types are silently skipped for forward compatibility
  with new CLI message types. Structural parse errors in known types still fail.
  """
  @spec parse_messages(list(map())) :: {:ok, [ClaudeCode.Message.t() | struct()]} | {:error, term()}
  def parse_messages(messages) when is_list(messages) do
    reduce_parsed(messages, &parse_message/1, [
      :unknown_message_type,
      :unknown_system_subtype,
      :unknown_event_type
    ])
  end

  @doc """
  Parses a newline-delimited JSON stream from the CLI.

  This is the format output by the CLI with `--output-format stream-json`.
  Each line is a complete JSON object representing a single message.
  Unknown message types are silently skipped for forward compatibility.
  """
  @spec parse_stream(String.t()) :: {:ok, [ClaudeCode.Message.t() | struct()]} | {:error, term()}
  def parse_stream(stream) when is_binary(stream) do
    stream
    |> String.split("\n", trim: true)
    |> decode_json_lines()
    |> case do
      {:ok, maps} -> parse_messages(maps)
      error -> error
    end
  end

  defp decode_json_lines(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {line, index}, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, json} -> {:cont, {:ok, [json | acc]}}
        {:error, error} -> {:halt, {:error, {:json_decode_error, index, error}}}
      end
    end)
    |> case do
      {:ok, maps} -> {:ok, Enum.reverse(maps)}
      error -> error
    end
  end

  # -- Content parsing --------------------------------------------------------

  @content_parsers Map.merge(
                     %{
                       "text" => &TextBlock.new/1,
                       "thinking" => &ThinkingBlock.new/1,
                       "redacted_thinking" => &RedactedThinkingBlock.new/1,
                       "tool_use" => &ToolUseBlock.new/1,
                       "tool_result" => &ToolResultBlock.new/1,
                       "server_tool_use" => &ServerToolUseBlock.new/1,
                       "web_search_tool_result" => &ServerToolResultBlock.new/1,
                       "web_fetch_tool_result" => &ServerToolResultBlock.new/1,
                       "code_execution_tool_result" => &ServerToolResultBlock.new/1,
                       "bash_code_execution_tool_result" => &ServerToolResultBlock.new/1,
                       "text_editor_code_execution_tool_result" => &ServerToolResultBlock.new/1,
                       "tool_search_tool_result" => &ServerToolResultBlock.new/1,
                       "mcp_tool_use" => &MCPToolUseBlock.new/1,
                       "mcp_tool_result" => &MCPToolResultBlock.new/1,
                       "image" => &ImageBlock.new/1,
                       "document" => &DocumentBlock.new/1,
                       "container_upload" => &ContainerUploadBlock.new/1,
                       "compaction" => &CompactionBlock.new/1
                     },
                     Application.compile_env(:claude_code, :content_parsers, %{})
                   )

  @doc """
  Parses a decoded JSON map into a content block struct.

  Normalizes keys and dispatches on `"type"` to the appropriate content
  module's `new/1` constructor.

  ## Examples

      iex> ClaudeCode.CLI.Parser.parse_content(%{"type" => "text", "text" => "Hello"})
      {:ok, %ClaudeCode.Content.TextBlock{type: :text, text: "Hello"}}

      iex> ClaudeCode.CLI.Parser.parse_content(%{"type" => "unknown"})
      {:error, {:unknown_content_type, "unknown"}}
  """
  @spec parse_content(map()) :: {:ok, ClaudeCode.Content.t() | struct()} | {:error, term()}
  def parse_content(%{"type" => _} = data) do
    data = normalize_keys(data)

    case Map.fetch(@content_parsers, data["type"]) do
      {:ok, parser} -> parser.(data)
      :error -> {:error, {:unknown_content_type, data["type"]}}
    end
  end

  def parse_content(data) when is_map(data), do: {:error, :missing_type}
  def parse_content(_), do: {:error, :missing_type}

  @doc """
  Parses a list of decoded JSON maps into content block structs.

  Unknown content block types are silently skipped for forward compatibility
  with new API types. Structural parse errors in known types still fail.
  """
  @spec parse_contents(list(map())) :: {:ok, [ClaudeCode.Content.t() | struct()]} | {:error, term()}
  def parse_contents(blocks) when is_list(blocks) do
    reduce_parsed(blocks, &parse_content/1, [:unknown_content_type])
  end

  # -- Content delta parsing --------------------------------------------------

  # -- Shared helpers ---------------------------------------------------------

  defp reduce_parsed(items, parse_fn, skip_tags) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case parse_fn.(item) do
        {:ok, parsed} ->
          {:cont, {:ok, [parsed | acc]}}

        {:error, {tag, _} = error} ->
          if tag in skip_tags, do: {:cont, {:ok, acc}}, else: {:halt, {:error, {:parse_error, index, error}}}

        {:error, error} ->
          {:halt, {:error, {:parse_error, index, error}}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end
end
