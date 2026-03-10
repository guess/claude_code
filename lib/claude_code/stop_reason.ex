defmodule ClaudeCode.StopReason do
  @moduledoc """
  Stop reason indicating why Claude stopped generating a response.

  Used by `ClaudeCode.Message.AssistantMessage` and `ClaudeCode.Message.ResultMessage`
  to describe why the model stopped.

  ## Values

    * `:end_turn` - Natural end of response
    * `:max_tokens` - Hit token limit
    * `:stop_sequence` - Hit a stop sequence
    * `:tool_use` - Stopped to use a tool
    * `:pause_turn` - Paused mid-turn
    * `:compaction` - Stopped for context compaction
    * `:refusal` - Model refused to respond
    * `:model_context_window_exceeded` - Context window exceeded
  """

  @type t ::
          :end_turn
          | :max_tokens
          | :stop_sequence
          | :tool_use
          | :pause_turn
          | :compaction
          | :refusal
          | :model_context_window_exceeded
          | String.t()

  @mapping %{
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

      iex> ClaudeCode.StopReason.parse("end_turn")
      :end_turn

      iex> ClaudeCode.StopReason.parse("tool_use")
      :tool_use

      iex> ClaudeCode.StopReason.parse("future_reason")
      "future_reason"

      iex> ClaudeCode.StopReason.parse(nil)
      nil

  """
  @spec parse(String.t() | nil) :: t() | String.t() | nil
  def parse(value) when is_binary(value), do: Map.get(@mapping, value, value)
  def parse(_value), do: nil
end
