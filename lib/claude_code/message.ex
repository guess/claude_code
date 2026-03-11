defmodule ClaudeCode.Message do
  @moduledoc """
  Utilities for working with messages from the Claude CLI.

  Messages can be system initialization, assistant responses, user tool results,
  result messages, stream events, conversation compaction boundaries, or
  informational messages (rate limits, tool progress, auth status, etc.).
  This module provides functions to parse and work with any message type.
  """

  alias ClaudeCode.Message.AssistantMessage
  alias ClaudeCode.Message.AuthStatusMessage
  alias ClaudeCode.Message.PartialAssistantMessage
  alias ClaudeCode.Message.PromptSuggestionMessage
  alias ClaudeCode.Message.RateLimitEvent
  alias ClaudeCode.Message.ResultMessage
  alias ClaudeCode.Message.SystemMessage
  alias ClaudeCode.Message.ToolProgressMessage
  alias ClaudeCode.Message.ToolUseSummaryMessage
  alias ClaudeCode.Message.UserMessage

  @type role :: :user | :assistant

  @doc """
  Parses a role string from CLI JSON into an atom.

  ## Examples

      iex> ClaudeCode.Message.parse_role("assistant")
      :assistant

      iex> ClaudeCode.Message.parse_role("user")
      :user

      iex> ClaudeCode.Message.parse_role("future_role")
      "future_role"

      iex> ClaudeCode.Message.parse_role(nil)
      nil
  """
  @spec parse_role(String.t() | nil) :: role() | String.t() | nil
  def parse_role("assistant"), do: :assistant
  def parse_role("user"), do: :user
  def parse_role(value) when is_binary(value), do: value
  def parse_role(_), do: nil

  @type stop_reason ::
          :end_turn
          | :max_tokens
          | :stop_sequence
          | :tool_use
          | :pause_turn
          | :compaction
          | :refusal
          | :model_context_window_exceeded
          | String.t()

  @stop_reason_mapping %{
    "end_turn" => :end_turn,
    "max_tokens" => :max_tokens,
    "stop_sequence" => :stop_sequence,
    "tool_use" => :tool_use,
    "pause_turn" => :pause_turn,
    "compaction" => :compaction,
    "refusal" => :refusal,
    "model_context_window_exceeded" => :model_context_window_exceeded
  }

  @doc """
  Parses a stop reason string from the CLI into an atom.

  Returns `nil` for nil input. Unrecognized values are kept as strings
  for forward compatibility without risking atom table exhaustion.

  ## Examples

      iex> ClaudeCode.Message.parse_stop_reason("end_turn")
      :end_turn

      iex> ClaudeCode.Message.parse_stop_reason("tool_use")
      :tool_use

      iex> ClaudeCode.Message.parse_stop_reason("future_reason")
      "future_reason"

      iex> ClaudeCode.Message.parse_stop_reason(nil)
      nil

  """
  @spec parse_stop_reason(String.t() | nil) :: stop_reason() | nil
  def parse_stop_reason(value) when is_binary(value), do: Map.get(@stop_reason_mapping, value, value)
  def parse_stop_reason(_value), do: nil

  @type t ::
          SystemMessage.t()
          | AssistantMessage.t()
          | UserMessage.t()
          | ResultMessage.t()
          | PartialAssistantMessage.t()
          | RateLimitEvent.t()
          | ToolProgressMessage.t()
          | ToolUseSummaryMessage.t()
          | AuthStatusMessage.t()
          | PromptSuggestionMessage.t()

  @doc """
  Checks if a value is any type of message.
  """
  @spec message?(any()) :: boolean()
  def message?(%AssistantMessage{}), do: true
  def message?(%UserMessage{}), do: true
  def message?(%ResultMessage{}), do: true
  def message?(%PartialAssistantMessage{}), do: true
  def message?(%RateLimitEvent{}), do: true
  def message?(%ToolProgressMessage{}), do: true
  def message?(%ToolUseSummaryMessage{}), do: true
  def message?(%AuthStatusMessage{}), do: true
  def message?(%PromptSuggestionMessage{}), do: true
  def message?(msg), do: SystemMessage.type?(msg)

  @type delta :: %{
          stop_reason: stop_reason() | nil,
          stop_sequence: String.t() | nil
        }

  @doc """
  Parses a message-level delta from a `message_delta` stream event.

  Extracts `stop_reason` via `parse_stop_reason/1` for consistency
  with `AssistantMessage` and `ResultMessage`.

  ## Examples

      iex> ClaudeCode.Message.parse_delta(%{"stop_reason" => "end_turn", "stop_sequence" => nil})
      %{stop_reason: :end_turn, stop_sequence: nil}

      iex> ClaudeCode.Message.parse_delta(nil)
      nil

  """
  @spec parse_delta(map() | nil) :: delta() | nil
  def parse_delta(nil), do: nil

  def parse_delta(delta) when is_map(delta) do
    %{
      stop_reason: parse_stop_reason(delta["stop_reason"]),
      stop_sequence: delta["stop_sequence"]
    }
  end

  @message_types [
    :system,
    :assistant,
    :user,
    :result,
    :stream_event,
    :rate_limit_event,
    :tool_progress,
    :tool_use_summary,
    :auth_status,
    :prompt_suggestion
  ]

  @doc """
  Returns the type atom of a message.

  All `ClaudeCode.Message.SystemMessage.*` subtypes (Init, CompactBoundary, HookStarted, etc.)
  return `:system` since they all carry `type: :system`. `SystemMessage.t()` is part of `t()`.
  """
  @spec message_type(t()) ::
          :system
          | :assistant
          | :user
          | :result
          | :stream_event
          | :rate_limit_event
          | :tool_progress
          | :tool_use_summary
          | :auth_status
          | :prompt_suggestion
  def message_type(%{type: type}) when type in @message_types, do: type
end
