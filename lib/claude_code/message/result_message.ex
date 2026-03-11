defmodule ClaudeCode.Message.ResultMessage do
  @moduledoc """
  Represents a result message from the Claude CLI.

  Result messages are the final message in a conversation, containing
  the final response, timing information, token usage, and cost.

  ## String.Chars Protocol

  `Result` implements `String.Chars`, so you can use it directly with
  `IO.puts/1` or string interpolation:

      {:ok, result} = ClaudeCode.query(session, "Hello")
      IO.puts(result)  # prints just the result text

  Matches the official SDK schema for successful results:
  ```
  {
    type: "result",
    subtype: "success",
    uuid: string,
    duration_ms: float,
    duration_api_ms: float,
    is_error: boolean,
    num_turns: int,
    result: string,
    stop_reason: string | null,
    session_id: string,
    total_cost_usd: float,
    usage: object,
    modelUsage: {model: ModelUsage},
    permission_denials: PermissionDenial[],
    structured_output?: unknown
  }
  ```

  And for error results:
  ```
  {
    type: "result",
    subtype: "error_max_turns" | "error_during_execution" | "error_max_budget_usd" | "error_max_structured_output_retries",
    uuid: string,
    duration_ms: float,
    duration_api_ms: float,
    is_error: boolean,
    num_turns: int,
    session_id: string,
    total_cost_usd: float,
    usage: object,
    modelUsage: {model: ModelUsage},
    permission_denials: PermissionDenial[],
    errors: string[]
  }
  ```
  """

  use ClaudeCode.JSONEncoder

  alias ClaudeCode.Model.Usage
  alias ClaudeCode.PermissionDenial

  @enforce_keys [
    :type,
    :subtype,
    :is_error,
    :duration_ms,
    :duration_api_ms,
    :num_turns,
    :session_id,
    :total_cost_usd,
    :usage
  ]
  defstruct [
    :type,
    :subtype,
    :is_error,
    :duration_ms,
    :duration_api_ms,
    :num_turns,
    :result,
    :session_id,
    :total_cost_usd,
    :usage,
    :uuid,
    :stop_reason,
    :model_usage,
    :permission_denials,
    :structured_output,
    :errors,
    :fast_mode_state
  ]

  @type subtype ::
          :success
          | :error_max_turns
          | :error_during_execution
          | :error_max_budget_usd
          | :error_max_structured_output_retries
          | String.t()

  @type t :: %__MODULE__{
          type: :result,
          subtype: subtype(),
          is_error: boolean(),
          duration_ms: float(),
          duration_api_ms: float(),
          num_turns: non_neg_integer(),
          result: String.t() | nil,
          session_id: String.t(),
          total_cost_usd: float(),
          usage: ClaudeCode.Usage.t(),
          uuid: String.t() | nil,
          stop_reason: ClaudeCode.StopReason.t() | nil,
          model_usage: %{String.t() => Usage.t()},
          permission_denials: [PermissionDenial.t()],
          structured_output: any() | nil,
          errors: [String.t()] | nil,
          fast_mode_state: String.t() | nil
        }

  @doc """
  Creates a new Result message from JSON data.

  ## Examples

      iex> Result.new(%{"type" => "result", "subtype" => "success", ...})
      {:ok, %Result{...}}

      iex> Result.new(%{"type" => "assistant"})
      {:error, :invalid_message_type}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom() | {:missing_fields, [atom()]}}
  def new(%{"type" => "result"} = json) do
    required_fields = [
      "subtype",
      "is_error",
      "duration_ms",
      "duration_api_ms",
      "num_turns",
      "session_id",
      "total_cost_usd",
      "usage"
    ]

    missing = Enum.filter(required_fields, &(not Map.has_key?(json, &1)))

    if Enum.empty?(missing) do
      message = %__MODULE__{
        type: :result,
        subtype: parse_subtype(json["subtype"]),
        is_error: json["is_error"],
        duration_ms: json["duration_ms"],
        duration_api_ms: json["duration_api_ms"],
        num_turns: json["num_turns"],
        result: json["result"],
        session_id: json["session_id"],
        total_cost_usd: parse_float(json["total_cost_usd"]),
        usage: ClaudeCode.Usage.parse(json["usage"]),
        uuid: json["uuid"],
        stop_reason: ClaudeCode.StopReason.parse(json["stop_reason"]),
        model_usage: Usage.parse(json["model_usage"]),
        permission_denials: parse_permission_denials(json["permission_denials"]),
        structured_output: json["structured_output"],
        errors: json["errors"],
        fast_mode_state: json["fast_mode_state"]
      }

      {:ok, message}
    else
      {:error, {:missing_fields, Enum.map(missing, &String.to_atom/1)}}
    end
  end

  def new(_), do: {:error, :invalid_message_type}

  @subtype_mapping %{
    "success" => :success,
    "error_max_turns" => :error_max_turns,
    "error_during_execution" => :error_during_execution,
    "error_max_budget_usd" => :error_max_budget_usd,
    "error_max_structured_output_retries" => :error_max_structured_output_retries
  }

  defp parse_subtype(value) when is_binary(value), do: Map.get(@subtype_mapping, value, value)

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0
  defp parse_float(_), do: 0.0

  defp parse_permission_denials(denials) when is_list(denials) do
    Enum.map(denials, &PermissionDenial.parse/1)
  end

  defp parse_permission_denials(_), do: []
end

defimpl String.Chars, for: ClaudeCode.Message.ResultMessage do
  def to_string(%{result: nil, errors: errors}) when is_list(errors) do
    "Error: " <> Enum.join(errors, ", ")
  end

  def to_string(%{result: nil}), do: ""
  def to_string(%{result: result}), do: result
end
