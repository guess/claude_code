defmodule ClaudeCode.History.SessionMessage do
  @moduledoc """
  A message from a session's conversation history, built via `parentUuid` chain walking.

  Matches the Python SDK's `SessionMessage` type. Contains chain metadata
  (`uuid`, `session_id`) alongside the parsed message content.

  The `:message` field contains parsed content — for assistant messages this
  includes `TextBlock`, `ToolUseBlock`, etc. structs; for user messages it
  contains either a string or a list of content blocks.

  ## Fields

    * `:type` - Message type: `:user` or `:assistant`
    * `:uuid` - UUID of this entry in the conversation chain
    * `:session_id` - Session UUID this message belongs to
    * `:message` - Parsed message content (see `ClaudeCode.Message.AssistantMessage`
      and `ClaudeCode.Message.UserMessage` for content structure)
    * `:parent_tool_use_id` - Tool use ID that triggered this message, if any
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.CLI.Parser
  alias ClaudeCode.Message.AssistantMessage

  defstruct [
    :type,
    :uuid,
    :session_id,
    :message,
    :parent_tool_use_id
  ]

  @type parsed_message ::
          ClaudeCode.Message.AssistantMessage.message()
          | ClaudeCode.Message.UserMessage.message_param()
          | map()

  @type t :: %__MODULE__{
          type: :user | :assistant,
          uuid: String.t(),
          session_id: String.t(),
          message: parsed_message(),
          parent_tool_use_id: String.t() | nil
        }

  @doc """
  Creates a `SessionMessage` from a raw JSONL transcript entry.

  Parses the inner message content into SDK structs (content blocks, usage, etc.)
  when possible. Falls back to the raw message map if parsing fails.
  """
  @spec from_entry(map()) :: t()
  def from_entry(entry) do
    type = if entry["type"] == "user", do: :user, else: :assistant
    raw_message = entry["message"]

    parsed_message = parse_inner_message(type, raw_message, entry)

    %__MODULE__{
      type: type,
      uuid: entry["uuid"] || "",
      session_id: entry["sessionId"] || "",
      message: parsed_message,
      parent_tool_use_id: entry["parentToolUseId"]
    }
  end

  defp parse_inner_message(:assistant, message_data, _entry) when is_map(message_data) do
    # parse_api_message expects content to be a list; history files may
    # contain abbreviated or non-standard content (e.g. plain string).
    if is_list(message_data["content"]) do
      case AssistantMessage.parse_api_message(message_data) do
        {:ok, parsed} -> parsed
        {:error, _} -> normalize_message(message_data)
      end
    else
      normalize_message(message_data)
    end
  end

  defp parse_inner_message(:user, message_data, _entry) when is_map(message_data) do
    content = message_data["content"]

    parsed_content =
      case content do
        c when is_binary(c) ->
          c

        c when is_list(c) ->
          case Parser.parse_contents(c) do
            {:ok, blocks} -> blocks
            {:error, _} -> c
          end

        _ ->
          []
      end

    %{
      content: parsed_content,
      role: :user
    }
  end

  defp parse_inner_message(_type, message_data, _entry), do: message_data

  defp normalize_message(data) when is_map(data), do: Parser.normalize_keys(data)
end
